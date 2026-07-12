import Foundation
import Observation

protocol DateProviding {
    var now: Date { get }
}

struct SystemDateProvider: DateProviding {
    var now: Date {
        Date()
    }
}

@Observable
final class SolitaireViewModel {
    static let maxUndoHistoryCount = 200
    private static let hintVisibilityDuration: TimeInterval = 1.5

    var state: GameState
    private(set) var isAutoFinishAvailable: Bool
    // Optimistic: true when any legal action exists (cheap check after every move);
    // set false when a full hint search comes back empty for the current position.
    private(set) var isHintAvailable: Bool
    private var redealState: GameState
    var selection: Selection? {
        didSet {
            selectedCardIDs = Set(selection?.cards.map(\.id) ?? [])
        }
    }
    private var selectedCardIDs: Set<UUID> = []
    private(set) var activeHint: HintAdvisor.Hint?
    private(set) var hintWiggleToken = UUID()
    private var hintAutoClearToken = UUID()
    var isDragging: Bool = false
    var pendingAutoMove: PendingAutoMove?
    private(set) var movesCount: Int = 0
    private(set) var score: Int = 0
    private(set) var gameStartedAt: Date = .now
    private var hasAppliedTimeBonus = false
    private(set) var finalElapsedSeconds: Int?
    private var pauseStartedAt: Date?
    private(set) var stockDrawCount: Int = 3
    private(set) var scoringDrawCount: Int = DrawMode.three.rawValue
    private var hasStartedTrackedGame = false
    private var isCurrentGameFinalized = false
    private var hintRequestsInCurrentGame: Int = 0
    private var undosUsedInCurrentGame: Int = 0
    private var usedRedealInCurrentGame = false
    private let dateProvider: any DateProviding
    @ObservationIgnored private let hintPlanner = HintPlanner()

    private var history: [GameSnapshot] = []

    struct PendingAutoMove: Equatable {
        let id: UUID
        let selection: Selection
        let destination: Destination
    }

    init(
        dateProvider: any DateProviding = SystemDateProvider(),
        variant: GameVariant = .klondike
    ) {
        self.dateProvider = dateProvider
        let startedAt = dateProvider.now
        let initialState = GameState.newGame(variant: variant)
        state = initialState
        isAutoFinishAvailable = AutoFinishPlanner.canAutoFinish(in: initialState)
        isHintAvailable = HintAdvisor.anyPlayerMoveExists(in: initialState)
        redealState = initialState
        gameStartedAt = startedAt
        hasStartedTrackedGame = false
        GameStatisticsStore.markTrackingStarted(for: variant, at: startedAt)
    }

    var gameVariant: GameVariant {
        state.variant
    }

    var isWin: Bool {
        state.isWon
    }

    var canUndo: Bool {
        !history.isEmpty && !isWin
    }

    var hintedCardIDs: Set<UUID> {
        switch activeHint {
        case .move(let move):
            return Set(move.selection.cards.map(\.id))
        case .stockTap, .none:
            return []
        }
    }

    var hintedDestination: Destination? {
        switch activeHint {
        case .move(let move):
            return move.destination
        case .stockTap, .none:
            return nil
        }
    }

    var isStockHinted: Bool {
        if case .stockTap = activeHint {
            return true
        }
        return false
    }

    var isWasteHinted: Bool {
        guard case .stockTap = activeHint else { return false }
        return state.stock.isEmpty && !state.waste.isEmpty
    }

    var hasActiveHint: Bool {
        activeHint != nil
    }

    var isClockAdvancing: Bool {
        pauseStartedAt == nil && finalElapsedSeconds == nil
    }

    func requestHint() {
        guard !isWin else {
            clearHint()
            return
        }

        guard let hint = hintPlanner.bestHint(in: state, stockDrawCount: stockDrawCount) else {
            clearHint()
            // The cheap availability check can't know the planner would come up empty
            // (e.g. a dead stock cycle); now that the full search has, keep the button
            // honest until the next state change re-evaluates it.
            isHintAvailable = false
            HapticManager.shared.play(.invalidDrop)
            return
        }

        activeHint = hint
        hintWiggleToken = UUID()
        scheduleHintAutoClear(for: hint)
        hintRequestsInCurrentGame += 1
        HapticManager.shared.play(.settingsSelection)
    }

    func clearHint() {
        hintAutoClearToken = UUID()
        activeHint = nil
    }

    private func scheduleHintAutoClear(for hint: HintAdvisor.Hint) {
        let token = UUID()
        hintAutoClearToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hintVisibilityDuration) { [weak self] in
            guard let self else { return }
            guard self.hintAutoClearToken == token else { return }
            guard self.activeHint == hint else { return }
            self.activeHint = nil
        }
    }

    func unfinalizedElapsedSecondsForStats(at date: Date = .now) -> Int {
        guard hasStartedTrackedGame, !isCurrentGameFinalized else { return 0 }
        return elapsedActiveSeconds(at: date)
    }

    func resetStatisticsTracking() {
        hasStartedTrackedGame = false
        isCurrentGameFinalized = true
        hintRequestsInCurrentGame = 0
        undosUsedInCurrentGame = 0
        usedRedealInCurrentGame = false
    }

    func displayScore(at date: Date = .now) -> Int {
        guard !hasAppliedTimeBonus else { return score }
        let elapsedSeconds = elapsedActiveSeconds(at: date)
        let maxBonus = Scoring.timedMaxBonus(for: scoringDrawCount)
        let bonus = Scoring.timeBonus(
            elapsedSeconds: elapsedSeconds,
            maxBonus: maxBonus,
            pointsLostPerSecond: Scoring.timedPointsLostPerSecond
        )
        return Scoring.clamped(score + bonus)
    }

    func elapsedActiveSeconds(at date: Date = .now) -> Int {
        if let finalElapsedSeconds {
            return finalElapsedSeconds
        }
        let effectiveNow = min(pauseStartedAt ?? date, date)
        return max(0, Int(effectiveNow.timeIntervalSince(gameStartedAt)))
    }

    @discardableResult
    func pauseTimeScoring(at date: Date = .now) -> Bool {
        guard !hasAppliedTimeBonus else { return false }
        guard pauseStartedAt == nil else { return false }
        pauseStartedAt = date
        return true
    }

    @discardableResult
    func resumeTimeScoring(at date: Date = .now) -> Bool {
        guard !hasAppliedTimeBonus else { return false }
        guard let pausedAt = pauseStartedAt else { return false }
        let pausedDuration = max(0, date.timeIntervalSince(pausedAt))
        gameStartedAt = gameStartedAt.addingTimeInterval(pausedDuration)
        pauseStartedAt = nil
        return true
    }

    func newGame(variant: GameVariant? = nil, drawMode: DrawMode = .three) {
        finalizeCurrentGameIfNeeded(didWin: isWin, endedAt: dateProvider.now)
        clearHint()
        let nextVariant = variant ?? state.variant
        let initialState = GameState.newGame(variant: nextVariant)
        state = initialState
        redealState = initialState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        movesCount = 0
        score = 0
        gameStartedAt = dateProvider.now
        hasAppliedTimeBonus = false
        finalElapsedSeconds = nil
        pauseStartedAt = nil
        applyNewGameVariantConfiguration(variant: nextVariant, drawMode: drawMode)
        GameStatisticsStore.markTrackingStarted(for: nextVariant, at: gameStartedAt)
        hasStartedTrackedGame = true
        isCurrentGameFinalized = false
        hintRequestsInCurrentGame = 0
        undosUsedInCurrentGame = 0
        usedRedealInCurrentGame = false
        history.removeAll()
        refreshAutoFinishAvailability()
    }

    func redeal() {
        finalizeCurrentGameIfNeeded(didWin: isWin, endedAt: dateProvider.now)
        clearHint()
        state = redealState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        movesCount = 0
        score = 0
        gameStartedAt = dateProvider.now
        hasAppliedTimeBonus = false
        finalElapsedSeconds = nil
        pauseStartedAt = nil
        applyRedealVariantConfiguration()
        GameStatisticsStore.markTrackingStarted(for: state.variant, at: gameStartedAt)
        hasStartedTrackedGame = true
        isCurrentGameFinalized = false
        hintRequestsInCurrentGame = 0
        undosUsedInCurrentGame = 0
        usedRedealInCurrentGame = true
        history.removeAll()
        refreshAutoFinishAvailability()
    }

    func undo() {
        guard !isWin else { return }
        guard let snapshot = history.popLast() else { return }
        clearHint()
        state = snapshot.state
        movesCount = snapshot.movesCount
        score = snapshot.score
        hasAppliedTimeBonus = snapshot.hasAppliedTimeBonus
        finalElapsedSeconds = nil
        undosUsedInCurrentGame += 1
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        SoundManager.shared.play(.undoMove)
        refreshAutoFinishAvailability()
    }

    func peekUndoSnapshot() -> GameSnapshot? {
        history.last
    }

    func persistencePayload() -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: movesCount,
            score: score,
            gameStartedAt: gameStartedAt,
            pauseStartedAt: pauseStartedAt,
            hasAppliedTimeBonus: hasAppliedTimeBonus,
            finalElapsedSeconds: finalElapsedSeconds,
            stockDrawCount: stockDrawCount,
            scoringDrawCount: scoringDrawCount,
            history: history,
            redealState: redealState,
            hasStartedTrackedGame: hasStartedTrackedGame,
            isCurrentGameFinalized: isCurrentGameFinalized,
            hintRequestsInCurrentGame: hintRequestsInCurrentGame,
            undosUsedInCurrentGame: undosUsedInCurrentGame,
            usedRedealInCurrentGame: usedRedealInCurrentGame
        )
    }

    @discardableResult
    func restore(from payload: SavedGamePayload) -> Bool {
        let now = dateProvider.now
        guard let sanitizedPayload = payload.sanitizedForRestore(at: now) else { return false }
        clearHint()
        let offlineDurationSinceSave = max(0, now.timeIntervalSince(sanitizedPayload.savedAt))
        state = sanitizedPayload.state
        movesCount = sanitizedPayload.movesCount
        score = sanitizedPayload.score
        gameStartedAt = sanitizedPayload.gameStartedAt
        pauseStartedAt = sanitizedPayload.pauseStartedAt
        hasAppliedTimeBonus = sanitizedPayload.hasAppliedTimeBonus
        finalElapsedSeconds = sanitizedPayload.finalElapsedSeconds
        if pauseStartedAt == nil, !hasAppliedTimeBonus {
            gameStartedAt = gameStartedAt.addingTimeInterval(offlineDurationSinceSave)
        }
        stockDrawCount = sanitizedPayload.stockDrawCount
        scoringDrawCount = sanitizedPayload.scoringDrawCount
        GameStatisticsStore.markTrackingStarted(for: state.variant, at: gameStartedAt)
        hasStartedTrackedGame = sanitizedPayload.hasStartedTrackedGame
        isCurrentGameFinalized = sanitizedPayload.isCurrentGameFinalized
        hintRequestsInCurrentGame = sanitizedPayload.hintRequestsInCurrentGame
        undosUsedInCurrentGame = sanitizedPayload.undosUsedInCurrentGame
        usedRedealInCurrentGame = sanitizedPayload.usedRedealInCurrentGame
        history = Array(sanitizedPayload.history.suffix(Self.maxUndoHistoryCount))
        var restoredRedealState = sanitizedPayload.redealState ?? history.first?.state ?? state
        restoredRedealState = normalizedRedealStateForCurrentVariant(
            from: restoredRedealState,
            stockDrawCount: stockDrawCount
        )
        redealState = restoredRedealState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        refreshAutoFinishAvailability()
        return true
    }

    func handleFoundationTap(index: Int) {
        if selection != nil || state.foundations[index].last != nil {
            HapticManager.shared.play(.cardPickUp)
        }
        if selection != nil {
            if tryMoveSelection(to: .foundation(index)) {
                return
            }
        } else if let topCard = state.foundations[index].last {
            let tappedSelection = Selection(source: .foundation(pile: index), cards: [topCard])
            if queueBestAutoMove(
                for: tappedSelection,
                playFailureFeedback: false
            ) {
                return
            }
        }
        isDragging = false
        selectFromFoundation(index: index)
    }

    func handleTableauTap(pileIndex: Int, cardIndex: Int?) {
        if let cardIndex {
            let pile = state.tableau[pileIndex]
            guard cardIndex < pile.count else { return }
            let card = pile[cardIndex]

            if handleVariantTableauTapIfNeeded(
                pile: pile,
                pileIndex: pileIndex,
                cardIndex: cardIndex,
                card: card
            ) {
                return
            }

            HapticManager.shared.play(.cardPickUp)
            let selectedCards = Array(pile[cardIndex...])
            guard canSelectTableauCards(selectedCards) else {
                selection = nil
                HapticManager.shared.play(.invalidDrop)
                return
            }
            let tappedSelection = Selection(
                source: .tableau(pile: pileIndex, index: cardIndex),
                cards: selectedCards
            )
            if selection?.source == tappedSelection.source {
                self.selection = nil
                return
            }

            // An active selection dropping onto this pile wins over auto-moving the
            // tapped card, so tap-select-then-tap-destination behaves as expected.
            if selection != nil, tryMoveSelection(to: .tableau(pileIndex)) {
                return
            }

            if queueBestAutoMove(for: tappedSelection) {
                return
            }

            isDragging = false
            selection = tappedSelection
        } else {
            if selection != nil {
                HapticManager.shared.play(.cardPickUp)
                _ = tryMoveSelection(to: .tableau(pileIndex))
            }
        }
    }

    func isSelected(card: Card) -> Bool {
        selectedCardIDs.contains(card.id)
    }

    @discardableResult
    func startDragFromFoundation(index: Int) -> Bool {
        guard let top = state.foundations[index].last else { return false }
        clearHint()
        selection = Selection(source: .foundation(pile: index), cards: [top])
        isDragging = true
        return true
    }

    @discardableResult
    func handleDrop(to destination: Destination) -> Bool {
        let moved = tryMoveSelection(to: destination)
        if !moved {
            selection = nil
        }
        isDragging = false
        return moved
    }

    func cancelDrag() {
        selection = nil
        isDragging = false
    }

    func clearPendingAutoMove() {
        pendingAutoMove = nil
    }

    func setStockDrawCount(_ count: Int) {
        stockDrawCount = count
    }

    func setScoringDrawCount(_ count: Int) {
        scoringDrawCount = count
    }

    func setWasteDrawCount(_ count: Int) {
        state.wasteDrawCount = max(0, count)
    }

    func incrementMovesCount() {
        movesCount += 1
    }

    private func applyNewGameVariantConfiguration(variant: GameVariant, drawMode: DrawMode) {
        switch variant {
        case .klondike:
            configureKlondikeNewGame(drawMode: drawMode)
        case .freecell, .yukon:
            configureStocklessNewGame()
        }
    }

    private func applyRedealVariantConfiguration() {
        switch state.variant {
        case .klondike:
            configureKlondikeRedeal()
        case .freecell, .yukon:
            configureStocklessRedeal()
        }
    }

    private func normalizedRedealStateForCurrentVariant(
        from state: GameState,
        stockDrawCount: Int
    ) -> GameState {
        switch state.variant {
        case .klondike:
            return sanitizeKlondikeRedealState(state, stockDrawCount: stockDrawCount)
        case .freecell, .yukon:
            return sanitizeStocklessRedealState(state)
        }
    }

    /// New-game configuration shared by the variants without a stock: draw counts
    /// stay at the draw-three defaults so time-bonus scoring has a defined basis,
    /// and no waste cards are ever fanned.
    func configureStocklessNewGame() {
        setStockDrawCount(DrawMode.three.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(0)
    }

    func configureStocklessRedeal() {
        setScoringDrawCount(stockDrawCount)
        setWasteDrawCount(0)
    }

    func sanitizeStocklessRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = 0
        return sanitizedState
    }

    private func handleVariantTableauTapIfNeeded(
        pile: [Card],
        pileIndex: Int,
        cardIndex: Int,
        card: Card
    ) -> Bool {
        switch state.variant {
        case .klondike, .yukon:
            return handleFaceDownTableauTap(
                pile: pile,
                pileIndex: pileIndex,
                cardIndex: cardIndex,
                card: card
            )
        case .freecell:
            return false
        }
    }

    /// Tap handling shared by the variants that deal face-down tableau cards:
    /// tapping an exposed face-down top flips it (a scored move); tapping a buried
    /// face-down card just clears the selection.
    @discardableResult
    private func handleFaceDownTableauTap(
        pile: [Card],
        pileIndex: Int,
        cardIndex: Int,
        card: Card
    ) -> Bool {
        guard !card.isFaceUp else { return false }
        guard cardIndex == pile.count - 1 else {
            selection = nil
            return true
        }
        clearHint()
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .flipTableauTop,
                cardIDs: [card.id]
            )
        )
        state.tableau[pileIndex][cardIndex].isFaceUp = true
        incrementMovesCount()
        applyScore(.turnOverTableauCard)
        SoundManager.shared.play(.cardFlipFaceUp)
        HapticManager.shared.play(.cardFlipFaceUp)
        refreshAutoFinishAvailability()
        selection = nil
        return true
    }

    /// Whether the given face-up run/group may be picked up under the current
    /// variant's rules. Also drives which tableau cards are accessibility elements.
    func canSelectTableauCards(_ cards: [Card]) -> Bool {
        switch state.variant {
        case .klondike, .yukon:
            return true
        case .freecell:
            return canSelectFreeCellTableauCards(cards)
        }
    }

    private func statisticsDrawCountForCurrentVariant() -> Int {
        switch state.variant {
        case .klondike:
            return scoringDrawCount
        case .freecell, .yukon:
            return 0
        }
    }

    func refreshAutoFinishAvailability() {
        isAutoFinishAvailable = AutoFinishPlanner.canAutoFinish(in: state)
        isHintAvailable = !isWin && HintAdvisor.anyPlayerMoveExists(in: state)
    }
}

extension SolitaireViewModel {
    func selectFromTableau(pileIndex: Int, cardIndex: Int) {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return }
        let cards = Array(pile[cardIndex...])
        selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
    }

    func selectFromFoundation(index: Int) {
        guard let top = state.foundations[index].last else { return }
        selection = Selection(source: .foundation(pile: index), cards: [top])
    }

    func selectFromFreeCell(index: Int) {
        guard state.freeCells.indices.contains(index), let card = state.freeCells[index] else { return }
        selection = Selection(source: .freeCell(slot: index), cards: [card])
    }

    func tryMoveSelection(to destination: Destination) -> Bool {
        guard let selection, let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1 else { return false }
            guard GameRules.canMoveToFoundation(
                card: movingCard,
                foundation: state.foundations[index]
            ) else { return false }
            clearHint()
            pushHistory(
                undoContext: UndoAnimationContext(
                    action: .moveSelection,
                    cardIDs: selection.cards.map(\.id)
                )
            )
            removeSelection(selection)
            state.foundations[index].append(movingCard)
            movesCount += 1
            applyScore(for: selection.source, destination: .foundation(index))
            applyTimeBonusIfWon()
            self.selection = nil
            SoundManager.shared.play(.cardPlaced)
            refreshAutoFinishAvailability()
            return true

        case .tableau(let index):
            guard canDrop(to: destination) else { return false }
            clearHint()
            pushHistory(
                undoContext: UndoAnimationContext(
                    action: .moveSelection,
                    cardIDs: selection.cards.map(\.id)
                )
            )
            removeSelection(selection)
            state.tableau[index].append(contentsOf: selection.cards)
            movesCount += 1
            applyScore(for: selection.source, destination: .tableau(index))
            applyTimeBonusIfWon()
            self.selection = nil
            SoundManager.shared.play(.cardPlaced)
            refreshAutoFinishAvailability()
            return true

        case .freeCell(let index):
            guard canDrop(to: destination) else { return false }
            clearHint()
            pushHistory(
                undoContext: UndoAnimationContext(
                    action: .moveSelection,
                    cardIDs: selection.cards.map(\.id)
                )
            )
            removeSelection(selection)
            state.freeCells[index] = movingCard
            movesCount += 1
            applyScore(for: selection.source, destination: .freeCell(index))
            applyTimeBonusIfWon()
            self.selection = nil
            SoundManager.shared.play(.cardPlaced)
            refreshAutoFinishAvailability()
            return true
        }
    }

    func removeSelection(_ selection: Selection) {
        switch selection.source {
        case .waste:
            _ = state.waste.popLast()
            if stockDrawCount == DrawMode.one.rawValue {
                state.wasteDrawCount = min(1, state.waste.count)
            } else {
                state.wasteDrawCount = max(0, state.wasteDrawCount - 1)
            }
        case .foundation(let pile):
            _ = state.foundations[pile].popLast()
        case .freeCell(let slot):
            state.freeCells[slot] = nil
        case .tableau(let pile, let index):
            var cards = state.tableau[pile]
            cards.removeSubrange(index..<cards.count)
            state.tableau[pile] = cards
            flipTopCardIfNeeded(in: pile)
        }
    }

    func flipTopCardIfNeeded(in pileIndex: Int) {
        switch state.variant {
        case .klondike, .yukon:
            flipFaceDownTopCardIfNeeded(in: pileIndex)
        case .freecell:
            break
        }
    }

    /// Flips a face-down card exposed at the top of a pile (a scored reveal),
    /// shared by the variants that deal face-down tableau cards.
    private func flipFaceDownTopCardIfNeeded(in pileIndex: Int) {
        guard let lastIndex = state.tableau[pileIndex].indices.last else { return }
        guard !state.tableau[pileIndex][lastIndex].isFaceUp else { return }
        state.tableau[pileIndex][lastIndex].isFaceUp = true
        applyScore(.turnOverTableauCard)
        SoundManager.shared.play(.cardFlipFaceUp)
        HapticManager.shared.play(.cardFlipFaceUp)
    }

    func pushHistory(undoContext: UndoAnimationContext? = nil) {
        history.append(
            GameSnapshot(
                state: state,
                movesCount: movesCount,
                score: score,
                hasAppliedTimeBonus: hasAppliedTimeBonus,
                undoContext: undoContext
            )
        )
        if history.count > Self.maxUndoHistoryCount {
            history.removeFirst()
        }
    }

    func applyScore(for source: Selection.Source, destination: Destination) {
        switch state.variant {
        case .klondike:
            applyKlondikeMoveScore(for: source, destination: destination)
        case .freecell:
            break
        case .yukon:
            applyYukonMoveScore(for: source, destination: destination)
        }
    }

    func applyScore(_ action: ScoringAction) {
        score = Scoring.applying(action, to: score)
    }

    func applyTimeBonusIfWon() {
        guard isWin, !hasAppliedTimeBonus else { return }
        let endedAt = dateProvider.now
        let elapsedSeconds = elapsedActiveSeconds(at: endedAt)
        let maxBonus = Scoring.timedMaxBonus(for: scoringDrawCount)
        let bonus = Scoring.timeBonus(
            elapsedSeconds: elapsedSeconds,
            maxBonus: maxBonus,
            pointsLostPerSecond: Scoring.timedPointsLostPerSecond
        )
        score = Scoring.clamped(score + bonus)
        finalElapsedSeconds = elapsedSeconds
        hasAppliedTimeBonus = true
        pauseStartedAt = nil
        finalizeCurrentGameIfNeeded(didWin: true, endedAt: endedAt)
    }

    func finalizeCurrentGameIfNeeded(didWin: Bool, endedAt: Date) {
        guard hasStartedTrackedGame, !isCurrentGameFinalized else { return }
        let elapsedSeconds = elapsedActiveSeconds(at: endedAt)
        GameStatisticsStore.update(for: state.variant) { stats in
            stats.recordCompletedGame(
                didWin: didWin,
                elapsedSeconds: elapsedSeconds,
                finalScore: score,
                drawCount: statisticsDrawCountForCurrentVariant(),
                hintsUsedInGame: hintRequestsInCurrentGame,
                undosUsedInGame: undosUsedInCurrentGame,
                usedRedealInGame: usedRedealInCurrentGame
            )
        }
        isCurrentGameFinalized = true
    }

    @discardableResult
    func queueNextAutoFinishMove() -> Bool {
        isDragging = false
        guard let move = AutoFinishPlanner.nextAutoFinishMove(in: state) else {
            return false
        }

        pendingAutoMove = PendingAutoMove(
            id: UUID(),
            selection: move.selection,
            destination: move.destination
        )
        return true
    }

    @discardableResult
    func queueBestAutoMove(
        for sourceSelection: Selection,
        playFailureFeedback: Bool = true
    ) -> Bool {
        isDragging = false
        guard let destination = TapMovePolicy.bestDestination(
            for: sourceSelection,
            in: state
        ) else {
            if playFailureFeedback {
                HapticManager.shared.play(.invalidDrop)
            }
            return false
        }

        pendingAutoMove = PendingAutoMove(
            id: UUID(),
            selection: sourceSelection,
            destination: destination
        )
        return true
    }

}
