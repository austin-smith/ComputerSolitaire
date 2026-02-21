import Foundation
import Observation

@Observable
final class SolitaireViewModel {
    static let maxUndoHistoryCount = 200
    private static let hintVisibilityDuration: TimeInterval = 1.5

    private(set) var state: GameState
    private(set) var isAutoFinishAvailable: Bool
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
    private var scoringDrawCount: Int = DrawMode.three.rawValue
    private var hasStartedTrackedGame = false
    private var isCurrentGameFinalized = false

    private var history: [GameSnapshot] = []

    struct PendingAutoMove: Equatable {
        let id: UUID
        let selection: Selection
        let destination: Destination
    }

    init() {
        let initialState = GameState.newGame()
        state = initialState
        isAutoFinishAvailable = AutoFinishPlanner.canAutoFinish(in: initialState)
        isHintAvailable = HintAdvisor.bestHint(
            in: initialState,
            stockDrawCount: DrawMode.three.rawValue
        ) != nil
        redealState = initialState
    }

    var isWin: Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
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

        guard let hint = HintAdvisor.bestHint(in: state, stockDrawCount: stockDrawCount) else {
            clearHint()
            HapticManager.shared.play(.invalidDrop)
            return
        }

        activeHint = hint
        hintWiggleToken = UUID()
        scheduleHintAutoClear(for: hint)
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

    func newGame(drawMode: DrawMode = .three) {
        finalizeCurrentGameIfNeeded(didWin: isWin, endedAt: .now)
        clearHint()
        let initialState = GameState.newGame()
        state = initialState
        redealState = initialState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        movesCount = 0
        score = 0
        gameStartedAt = .now
        hasAppliedTimeBonus = false
        finalElapsedSeconds = nil
        pauseStartedAt = nil
        stockDrawCount = drawMode.rawValue
        scoringDrawCount = drawMode.rawValue
        hasStartedTrackedGame = true
        isCurrentGameFinalized = false
        state.wasteDrawCount = 0
        history.removeAll()
        refreshAutoFinishAvailability()
    }

    func redeal() {
        finalizeCurrentGameIfNeeded(didWin: isWin, endedAt: .now)
        clearHint()
        state = redealState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        movesCount = 0
        score = 0
        gameStartedAt = .now
        hasAppliedTimeBonus = false
        finalElapsedSeconds = nil
        pauseStartedAt = nil
        scoringDrawCount = stockDrawCount
        hasStartedTrackedGame = true
        isCurrentGameFinalized = false
        state.wasteDrawCount = min(max(0, state.wasteDrawCount), min(stockDrawCount, state.waste.count))
        history.removeAll()
        refreshAutoFinishAvailability()
    }

    func updateDrawMode(_ drawMode: DrawMode) {
        clearHint()
        stockDrawCount = drawMode.rawValue
        if drawMode == .one {
            state.wasteDrawCount = min(1, state.waste.count)
        } else {
            state.wasteDrawCount = min(state.wasteDrawCount, drawMode.rawValue)
        }
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        refreshAutoFinishAvailability()
    }

    func visibleWasteCards() -> [Card] {
        let count = min(state.wasteDrawCount, stockDrawCount)
        return Array(state.waste.suffix(count))
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
            isCurrentGameFinalized: isCurrentGameFinalized
        )
    }

    @discardableResult
    func restore(from payload: SavedGamePayload) -> Bool {
        guard let sanitizedPayload = payload.sanitizedForRestore() else { return false }
        clearHint()
        let offlineDurationSinceSave = max(0, Date().timeIntervalSince(sanitizedPayload.savedAt))
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
        hasStartedTrackedGame = sanitizedPayload.hasStartedTrackedGame
        isCurrentGameFinalized = sanitizedPayload.isCurrentGameFinalized
        history = Array(sanitizedPayload.history.suffix(Self.maxUndoHistoryCount))
        var restoredRedealState = sanitizedPayload.redealState ?? history.first?.state ?? state
        restoredRedealState.wasteDrawCount = min(
            max(0, restoredRedealState.wasteDrawCount),
            min(stockDrawCount, restoredRedealState.waste.count)
        )
        redealState = restoredRedealState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        refreshAutoFinishAvailability()
        return true
    }

    func handleStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        if state.stock.isEmpty {
            recycleWaste()
        } else {
            drawFromStock()
        }
    }

    func handleWasteTap() {
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return }
        HapticManager.shared.play(.cardPickUp)
        let wasteSelection = Selection(source: .waste, cards: [top])
        if queueBestAutoMove(for: wasteSelection) {
            return
        }
        if selection?.source == .waste {
            selection = nil
            return
        }
        isDragging = false
        selection = wasteSelection
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

            if !card.isFaceUp {
                if cardIndex == pile.count - 1 {
                    clearHint()
                    pushHistory(
                        undoContext: UndoAnimationContext(
                            action: .flipTableauTop,
                            cardIDs: [card.id]
                        )
                    )
                    state.tableau[pileIndex][cardIndex].isFaceUp = true
                    movesCount += 1
                    applyScore(.turnOverTableauCard)
                    SoundManager.shared.play(.cardFlipFaceUp)
                    HapticManager.shared.play(.cardFlipFaceUp)
                    refreshAutoFinishAvailability()
                }
                selection = nil
                return
            }

            HapticManager.shared.play(.cardPickUp)
            let tappedSelection = Selection(
                source: .tableau(pile: pileIndex, index: cardIndex),
                cards: Array(pile[cardIndex...])
            )
            if selection?.source == tappedSelection.source {
                self.selection = nil
                return
            }

            if queueBestAutoMove(for: tappedSelection) {
                return
            }

            if selection != nil, tryMoveSelection(to: .tableau(pileIndex)) {
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
    func startDragFromWaste() -> Bool {
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return false }
        clearHint()
        selection = Selection(source: .waste, cards: [top])
        isDragging = true
        return true
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
    func startDragFromTableau(pileIndex: Int, cardIndex: Int) -> Bool {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return false }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return false }
        clearHint()
        let cards = Array(pile[cardIndex...])
        selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
        isDragging = true
        return true
    }

    func canDrop(to destination: Destination) -> Bool {
        guard let selection, let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1 else { return false }
            return GameRules.canMoveToFoundation(
                card: movingCard,
                foundation: state.foundations[index]
            )
        case .tableau(let index):
            return GameRules.canMoveToTableau(
                card: movingCard,
                destinationPile: state.tableau[index]
            )
        }
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

    func refreshAutoFinishAvailability() {
        isAutoFinishAvailable = AutoFinishPlanner.canAutoFinish(in: state)
        isHintAvailable = !isWin && HintAdvisor.bestHint(in: state, stockDrawCount: stockDrawCount) != nil
    }
}

private extension SolitaireViewModel {
    func drawFromStock() {
        guard !state.stock.isEmpty else { return }
        clearHint()
        let drawCount = min(stockDrawCount, state.stock.count)
        let drawnCardIDs = (0..<drawCount).map { offset in
            state.stock[state.stock.count - 1 - offset].id
        }
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .drawFromStock,
                cardIDs: drawnCardIDs
            )
        )
        for _ in 0..<drawCount {
            var card = state.stock.removeLast()
            card.isFaceUp = true
            state.waste.append(card)
        }
        state.wasteDrawCount = drawCount
        movesCount += 1
        SoundManager.shared.play(.cardDrawFromStock)
        HapticManager.shared.play(.stockDraw)
        refreshAutoFinishAvailability()
    }

    func recycleWaste() {
        guard state.stock.isEmpty, !state.waste.isEmpty else { return }
        clearHint()
        let visibleWasteIDs = visibleWasteCards().map(\.id)
        let animatedWasteIDs = visibleWasteIDs.isEmpty
            ? [state.waste.last?.id].compactMap { $0 }
            : visibleWasteIDs
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .recycleWaste,
                cardIDs: animatedWasteIDs
            )
        )
        var newStock: [Card] = []
        for card in state.waste.reversed() {
            var newCard = card
            newCard.isFaceUp = false
            newStock.append(newCard)
        }
        state.stock = newStock
        state.waste.removeAll()
        state.wasteDrawCount = 0
        movesCount += 1
        if stockDrawCount == DrawMode.one.rawValue {
            applyScore(.recycleWasteInDrawOne)
        }
        SoundManager.shared.play(.wasteRecycleToStock)
        HapticManager.shared.play(.wasteRecycle)
        refreshAutoFinishAvailability()
    }

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

    func tryMoveSelection(to destination: Destination) -> Bool {
        guard let selection, let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1 else { return false }
            guard GameRules.canMoveToFoundation(card: movingCard, foundation: state.foundations[index]) else { return false }
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
            guard GameRules.canMoveToTableau(card: movingCard, destinationPile: state.tableau[index]) else { return false }
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
        case .tableau(let pile, let index):
            var cards = state.tableau[pile]
            cards.removeSubrange(index..<cards.count)
            state.tableau[pile] = cards
            flipTopCardIfNeeded(in: pile)
        }
    }

    func flipTopCardIfNeeded(in pileIndex: Int) {
        guard let lastIndex = state.tableau[pileIndex].indices.last else { return }
        if !state.tableau[pileIndex][lastIndex].isFaceUp {
            state.tableau[pileIndex][lastIndex].isFaceUp = true
            applyScore(.turnOverTableauCard)
            SoundManager.shared.play(.cardFlipFaceUp)
            HapticManager.shared.play(.cardFlipFaceUp)
        }
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
        switch (source, destination) {
        case (.waste, .tableau):
            applyScore(.wasteToTableau)
        case (.waste, .foundation):
            applyScore(.wasteToFoundation)
        case (.tableau, .foundation):
            applyScore(.tableauToFoundation)
        case (.foundation, .tableau):
            applyScore(.foundationToTableau)
        default:
            break
        }
    }

    func applyScore(_ action: ScoringAction) {
        score = Scoring.applying(action, to: score)
    }

    func applyTimeBonusIfWon() {
        guard isWin, !hasAppliedTimeBonus else { return }
        let endedAt = Date()
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
        GameStatisticsStore.update { stats in
            stats.recordCompletedGame(
                didWin: didWin,
                elapsedSeconds: elapsedSeconds,
                finalScore: score,
                drawCount: scoringDrawCount
            )
        }
        isCurrentGameFinalized = true
    }

    @discardableResult
    func queueBestAutoMove(
        for sourceSelection: Selection,
        playFailureFeedback: Bool = true
    ) -> Bool {
        isDragging = false
        guard let destination = AutoMoveAdvisor.bestAdvisableDestination(
            for: sourceSelection,
            in: state,
            stockDrawCount: stockDrawCount
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
