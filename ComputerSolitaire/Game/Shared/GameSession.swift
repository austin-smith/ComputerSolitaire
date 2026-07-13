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
    /// The most recent stock-onto-tableau deal (Spider's row, Scorpion's
    /// three cards), published for the board's deal-flight animation. An
    /// explicit event rather than an inferred state diff, so restores, undos,
    /// and game switches can never replay a deal that already happened. Card
    /// IDs are in stock order, matching the deal's undo context.
    struct TableauDealEvent: Equatable {
        let id: UUID
        let dealtCardIDs: [UUID]
    }
    private(set) var latestTableauDealEvent: TableauDealEvent?

    /// Publishes a just-executed stock-onto-tableau deal for the board's
    /// flight animation; called by the variant session extensions.
    func publishTableauDealEvent(dealtCardIDs: [UUID]) {
        latestTableauDealEvent = TableauDealEvent(id: UUID(), dealtCardIDs: dealtCardIDs)
    }
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
    /// The nine-hole Golf match in progress; meaningless (and left at its
    /// fresh value) for every other variant. A fresh deal abandons it, a
    /// statistics reset revokes its eligibility, and redeal and undo leave it
    /// alone (undo snapshots deliberately exclude it, so undo can never cross
    /// a hole boundary); the match methods in `GameSessionGolf.swift` drive
    /// everything else.
    var golfMatch = GolfMatchState()
    /// Internal so variant session extensions (Golf's hole advance) share the
    /// injected clock.
    let dateProvider: any DateProviding
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
        GameStatisticsStore.markTrackingStarted(for: gameMode, at: startedAt)
    }

    var gameVariant: GameVariant {
        state.variant
    }

    /// The game this session currently hosts; keys its save slot and its
    /// statistics bucket. Spider's suit count is derived from the deal; the
    /// draw count is session state.
    var gameMode: GameMode {
        GameMode(
            variant: state.variant,
            drawMode: DrawMode(rawValue: stockDrawCount) ?? .three,
            spiderSuitCount: state.spiderSuitCount ?? .two
        )
    }

    var isWin: Bool {
        state.isWon
    }

    // A completed Golf match's final board is an archive: its hole score is
    // already banked into the scorecard and its statistics are recorded, so
    // no gameplay command may mutate it. These two properties are the single
    // gate for every entry point — toolbar, macOS menu, keyboard shortcut.
    var canUndo: Bool {
        !history.isEmpty && !isWin && !golfMatch.isComplete
    }

    /// Whether the current deal may be replayed. Redealing under a completed
    /// Golf match would run a hidden tracked deal beneath the match summary
    /// and finalize it as a phantom loss when the next match starts.
    var canRedeal: Bool {
        !golfMatch.isComplete
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
        if gameVariant == .golf {
            // The scorecard plays on, but a match holding pre-reset holes can
            // no longer finalize into the fresh statistics bucket.
            golfMatch.countsTowardStatistics = false
        }
    }

    func displayScore(at date: Date = .now) -> Int {
        guard !hasAppliedTimeBonus else { return score }
        let elapsedSeconds = elapsedActiveSeconds(at: date)
        let maxBonus = winTimeMaxBonus
        let bonus = Scoring.timeBonus(
            elapsedSeconds: elapsedSeconds,
            maxBonus: maxBonus,
            pointsLostPerSecond: Scoring.timedPointsLostPerSecond
        )
        return Scoring.clamped(score + bonus, for: state.variant)
    }

    /// A positive win bonus is perverse under Golf's lower-is-better stroke
    /// scoring, so Golf's basis is zero; every other variant keeps the
    /// draw-count basis.
    var winTimeMaxBonus: Int {
        state.variant.lowerScoreIsBetter ? 0 : Scoring.timedMaxBonus(for: scoringDrawCount)
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

    /// Finalizes the current game into its statistics and deals a fresh one;
    /// `nil` replays the current mode.
    func newGame(mode: GameMode? = nil) {
        finalizeCurrentGameIfNeeded(didWin: isWin, endedAt: dateProvider.now)
        startGame(mode: mode ?? gameMode)
    }

    /// Activates `mode` without finalizing the current game's statistics, restoring the
    /// mode's stashed session when one is available. Deals a fresh game when `payload`
    /// is missing, belongs to another game, or fails restore sanitization.
    @discardableResult
    func activateGame(_ mode: GameMode, restoringFrom payload: SavedGamePayload?) -> Bool {
        if let payload, payload.gameMode == mode, restore(from: payload) {
            return true
        }
        startGame(mode: mode)
        return false
    }

    private func startGame(mode: GameMode) {
        clearHint()
        let initialState = GameState.newGame(
            variant: mode.variant,
            spiderSuitCount: mode.spiderSuitCount ?? .two
        )
        // A fresh deal abandons any Golf match in progress. `dealNextGolfHole`
        // restores the match around this reset when advancing holes, and
        // `activateGame` re-adopts a stashed match through its payload restore.
        golfMatch = GolfMatchState()
        state = initialState
        redealState = initialState
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        latestTableauDealEvent = nil
        movesCount = 0
        score = 0
        gameStartedAt = dateProvider.now
        hasAppliedTimeBonus = false
        finalElapsedSeconds = nil
        pauseStartedAt = nil
        applyNewGameVariantConfiguration(variant: mode.variant, drawMode: mode.drawMode ?? .three)
        GameStatisticsStore.markTrackingStarted(for: gameMode, at: gameStartedAt)
        hasStartedTrackedGame = true
        isCurrentGameFinalized = false
        hintRequestsInCurrentGame = 0
        undosUsedInCurrentGame = 0
        usedRedealInCurrentGame = false
        history.removeAll()
        refreshAutoFinishAvailability()
    }

    func redeal() {
        guard canRedeal else { return }
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
        GameStatisticsStore.markTrackingStarted(for: gameMode, at: gameStartedAt)
        hasStartedTrackedGame = true
        isCurrentGameFinalized = false
        hintRequestsInCurrentGame = 0
        undosUsedInCurrentGame = 0
        usedRedealInCurrentGame = true
        history.removeAll()
        refreshAutoFinishAvailability()
    }

    func undo() {
        guard canUndo else { return }
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
            usedRedealInCurrentGame: usedRedealInCurrentGame,
            golfMatch: state.variant == .golf ? golfMatch : nil
        )
    }

    @discardableResult
    func restore(from payload: SavedGamePayload) -> Bool {
        let now = dateProvider.now
        guard let sanitizedPayload = payload.sanitizedForRestore(at: now) else { return false }
        clearHint()
        latestTableauDealEvent = nil
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
        GameStatisticsStore.markTrackingStarted(for: gameMode, at: gameStartedAt)
        hasStartedTrackedGame = sanitizedPayload.hasStartedTrackedGame
        isCurrentGameFinalized = sanitizedPayload.isCurrentGameFinalized
        hintRequestsInCurrentGame = sanitizedPayload.hintRequestsInCurrentGame
        undosUsedInCurrentGame = sanitizedPayload.undosUsedInCurrentGame
        usedRedealInCurrentGame = sanitizedPayload.usedRedealInCurrentGame
        golfMatch = sanitizedPayload.golfMatch ?? GolfMatchState()
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
        guard state.variant.playerBuildsFoundations else { return }
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
        guard state.variant.allowsFoundationRollback else { return false }
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

    func setInitialScore(_ initialScore: Int) {
        score = Scoring.clamped(initialScore, for: state.variant)
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
        case .freecell, .yukon, .scorpion:
            configureWastelessNewGame()
        case .spider:
            configureSpiderNewGame()
        case .pyramid:
            configurePyramidNewGame()
        case .tripeaks:
            configureTriPeaksNewGame()
        case .golf:
            configureGolfNewGame()
        case .fortyThieves:
            configureFortyThievesNewGame()
        }
    }

    private func applyRedealVariantConfiguration() {
        switch state.variant {
        case .klondike:
            configureKlondikeRedeal()
        case .freecell, .yukon, .scorpion:
            configureWastelessRedeal()
        case .spider:
            configureSpiderRedeal()
        case .pyramid:
            configurePyramidRedeal()
        case .tripeaks:
            configureTriPeaksRedeal()
        case .golf:
            configureGolfRedeal()
        case .fortyThieves:
            configureFortyThievesRedeal()
        }
    }

    private func normalizedRedealStateForCurrentVariant(
        from state: GameState,
        stockDrawCount: Int
    ) -> GameState {
        switch state.variant {
        case .klondike:
            return sanitizeKlondikeRedealState(state, stockDrawCount: stockDrawCount)
        case .freecell, .yukon, .spider, .scorpion:
            return sanitizeWastelessRedealState(state)
        case .pyramid:
            return sanitizePyramidRedealState(state)
        case .tripeaks:
            return sanitizeTriPeaksRedealState(state)
        case .golf:
            return sanitizeGolfRedealState(state)
        case .fortyThieves:
            return sanitizeFortyThievesRedealState(state)
        }
    }

    /// New-game configuration shared by the variants that never draw through a
    /// waste: draw counts stay at the draw-three defaults so time-bonus scoring
    /// has a defined basis, and no waste cards are ever fanned.
    func configureWastelessNewGame() {
        setStockDrawCount(DrawMode.three.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(0)
    }

    func configureWastelessRedeal() {
        setScoringDrawCount(stockDrawCount)
        setWasteDrawCount(0)
    }

    func sanitizeWastelessRedealState(_ baseState: GameState) -> GameState {
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
        case .klondike, .yukon, .spider, .scorpion:
            return handleFaceDownTableauTap(
                pile: pile,
                pileIndex: pileIndex,
                cardIndex: cardIndex,
                card: card
            )
        case .golf:
            return handleGolfTableauTap(
                pile: pile,
                pileIndex: pileIndex,
                cardIndex: cardIndex,
                card: card
            )
        case .freecell, .pyramid, .tripeaks, .fortyThieves:
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
        applyTableauRevealScoreIfNeeded()
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
        case .klondike, .yukon, .scorpion:
            return true
        case .freecell:
            return canSelectFreeCellTableauCards(cards)
        case .spider:
            return SharedGameRules.isDescendingSameSuitRun(cards)
        case .golf, .fortyThieves:
            // Only the exposed card of a column can ever move.
            return cards.count == 1
        case .pyramid, .tripeaks:
            // Pyramid and TriPeaks have no tableau piles.
            return false
        }
    }

    /// The draw-mode basis statistics record under: always the game's own
    /// mode, so the bucket and the high-score field it routes to can never
    /// diverge — legacy saves may carry a `scoringDrawCount` that differs
    /// from the mode they live and display as.
    private func statisticsDrawCountForCurrentVariant() -> Int {
        gameMode.drawMode?.rawValue ?? 0
    }

    func refreshAutoFinishAvailability() {
        isAutoFinishAvailable = AutoFinishPlanner.canAutoFinish(in: state)
        isHintAvailable = !isWin && HintAdvisor.anyPlayerMoveExists(in: state)
    }
}

// MARK: - Stock & waste (variants that deal from a stock)

extension SolitaireViewModel {
    func handleStockTap() {
        switch state.variant {
        case .klondike:
            handleKlondikeStockTap()
        case .spider:
            handleSpiderStockTap()
        case .scorpion:
            handleScorpionStockTap()
        case .pyramid:
            handlePyramidStockTap()
        case .tripeaks:
            handleTriPeaksStockTap()
        case .golf:
            handleGolfStockTap()
        case .fortyThieves:
            handleFortyThievesStockTap()
        case .freecell, .yukon:
            break
        }
    }

    /// Whether tapping the stock slot can still do anything: draw, or recycle the
    /// waste (Pyramid stops recycling once its passes are spent).
    var canInteractWithStock: Bool {
        switch state.variant {
        case .klondike:
            return !(state.stock.isEmpty && state.waste.isEmpty)
        case .pyramid:
            return !state.stock.isEmpty || PyramidGameRules.canRecycleWaste(in: state)
        case .tripeaks, .golf, .fortyThieves:
            // Single pass with no recycles: an empty stock is dead.
            return !state.stock.isEmpty
        case .spider, .scorpion:
            // Spider's and Scorpion's stocks render through their own views;
            // recorded for honesty.
            return !state.stock.isEmpty
        case .freecell, .yukon:
            return false
        }
    }

    func visibleWasteCards() -> [Card] {
        switch state.variant {
        case .klondike:
            let count = min(state.wasteDrawCount, stockDrawCount)
            return Array(state.waste.suffix(count))
        case .pyramid, .tripeaks, .golf, .fortyThieves:
            return Array(state.waste.suffix(min(1, state.wasteDrawCount)))
        case .freecell, .yukon, .spider, .scorpion:
            return []
        }
    }

    func handleWasteTap() {
        guard state.variant.dealsFromStock else { return }
        // The TriPeaks and Golf waste tops are the match target, never a mover.
        guard state.variant != .tripeaks, state.variant != .golf else { return }
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return }
        HapticManager.shared.play(.cardPickUp)

        // An active selection pairing with the waste top wins over auto-moving
        // the waste card, so tap-select-then-tap-waste removes the pair the
        // player chose (Pyramid; no selection can land on the waste elsewhere).
        if selection != nil, tryMoveSelection(to: .waste) {
            return
        }

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

    @discardableResult
    func startDragFromWaste() -> Bool {
        guard state.variant.dealsFromStock else { return false }
        // The TriPeaks and Golf waste tops are the match target, never a mover.
        guard state.variant != .tripeaks, state.variant != .golf else { return false }
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return false }
        clearHint()
        selection = Selection(source: .waste, cards: [top])
        isDragging = true
        return true
    }

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
        if state.variant == .tripeaks {
            // A stock flip breaks the scoring chain. This lives here — not in
            // the TriPeaks stock handler — so any draw path preserves the
            // invariant; `TriPeaksPlanner.apply(.draw)` mirrors it.
            state.triPeaksChainLength = 0
        }
        setWasteDrawCount(drawCount)
        incrementMovesCount()
        SoundManager.shared.play(.cardDrawFromStock)
        HapticManager.shared.play(.stockDraw)
        refreshAutoFinishAvailability()
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
        guard state.variant.allowsFoundationRollback else { return }
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
            if state.variant == .spider {
                resolveCompletedSpiderRuns()
            } else if state.variant == .scorpion {
                resolveCompletedScorpionRuns()
            }
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

        case .pyramid, .waste, .discard:
            if state.variant == .tripeaks {
                return performTriPeaksMove(selection: selection, to: destination)
            }
            if state.variant == .golf {
                return performGolfMove(selection: selection, to: destination)
            }
            return performPyramidMove(selection: selection, to: destination)
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
        case .pyramid(let index):
            state.pyramid[index] = nil
        case .triPeaks(let index):
            state.triPeaks[index] = nil
        }
    }

    func flipTopCardIfNeeded(in pileIndex: Int) {
        switch state.variant {
        case .klondike, .yukon, .spider, .scorpion:
            flipFaceDownTopCardIfNeeded(in: pileIndex)
        case .freecell, .pyramid, .tripeaks, .golf, .fortyThieves:
            break
        }
    }

    /// Flips a face-down card exposed at the top of a pile, shared by the
    /// variants that deal face-down tableau cards.
    private func flipFaceDownTopCardIfNeeded(in pileIndex: Int) {
        guard let lastIndex = state.tableau[pileIndex].indices.last else { return }
        guard !state.tableau[pileIndex][lastIndex].isFaceUp else { return }
        state.tableau[pileIndex][lastIndex].isFaceUp = true
        applyTableauRevealScoreIfNeeded()
        SoundManager.shared.play(.cardFlipFaceUp)
        HapticManager.shared.play(.cardFlipFaceUp)
    }

    /// Reveals score in the Klondike-family variants; Spider's classic scheme
    /// scores card moves and completed runs only.
    private func applyTableauRevealScoreIfNeeded() {
        guard state.variant != .spider else { return }
        applyScore(.turnOverTableauCard)
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
        case .spider:
            applySpiderMoveScore(for: source, destination: destination)
        case .scorpion:
            // Scorpion scores reveals (via the shared flip path) and banked
            // runs only; tableau moves themselves are free.
            break
        case .pyramid:
            applyPyramidMoveScore(for: destination)
        case .tripeaks:
            // TriPeaks chain scoring reads the before/after states, so
            // `performTriPeaksMove` applies it directly.
            break
        case .golf:
            // Golf stroke scoring reads the after state, so `performGolfMove`
            // applies it directly.
            break
        case .fortyThieves:
            applyFortyThievesMoveScore(for: source, destination: destination)
        }
    }

    func applyScore(_ action: ScoringAction) {
        score = Scoring.applying(action, to: score, variant: state.variant)
    }

    func applyTimeBonusIfWon() {
        guard isWin, !hasAppliedTimeBonus else { return }
        let endedAt = dateProvider.now
        let elapsedSeconds = elapsedActiveSeconds(at: endedAt)
        let maxBonus = winTimeMaxBonus
        let bonus = Scoring.timeBonus(
            elapsedSeconds: elapsedSeconds,
            maxBonus: maxBonus,
            pointsLostPerSecond: Scoring.timedPointsLostPerSecond
        )
        score = Scoring.clamped(score + bonus, for: state.variant)
        finalElapsedSeconds = elapsedSeconds
        hasAppliedTimeBonus = true
        pauseStartedAt = nil
        finalizeCurrentGameIfNeeded(didWin: true, endedAt: endedAt)
    }

    func finalizeCurrentGameIfNeeded(didWin: Bool, endedAt: Date) {
        guard hasStartedTrackedGame, !isCurrentGameFinalized else { return }
        let elapsedSeconds = elapsedActiveSeconds(at: endedAt)
        // A Golf hole's stroke score is final only once the hole is over (won
        // or dead); a mid-hole abandonment finalizes as a played game like any
        // variant, but its score is an unfinished snapshot and must not enter
        // the best-hole record.
        let completedGolfHoleScore = isGolfHoleOver ? score : nil
        GameStatisticsStore.update(for: gameMode) { stats in
            stats.recordCompletedGame(
                didWin: didWin,
                elapsedSeconds: elapsedSeconds,
                finalScore: score,
                drawCount: statisticsDrawCountForCurrentVariant(),
                spiderSuitCount: state.spiderSuitCount,
                lowerScoreIsBetter: state.variant.lowerScoreIsBetter,
                hintsUsedInGame: hintRequestsInCurrentGame,
                undosUsedInGame: undosUsedInCurrentGame,
                usedRedealInGame: usedRedealInCurrentGame
            )
            if let completedGolfHoleScore {
                stats.recordCompletedGolfHole(score: completedGolfHoleScore)
            }
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
