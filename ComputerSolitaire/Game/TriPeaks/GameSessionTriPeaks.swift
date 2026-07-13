import Foundation

extension SolitaireViewModel {
    // MARK: Configuration

    /// TriPeaks draws a single card to the waste; time-bonus scoring keeps the
    /// draw-three basis the other stockless-choice variants use.
    func configureTriPeaksNewGame() {
        setStockDrawCount(DrawMode.one.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(min(1, state.waste.count))
    }

    func configureTriPeaksRedeal() {
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(min(1, state.waste.count))
    }

    func sanitizeTriPeaksRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = min(1, sanitizedState.waste.count)
        // Chain cards are all in the waste beyond the deal's starter card.
        sanitizedState.triPeaksChainLength = min(
            max(0, sanitizedState.triPeaksChainLength),
            max(0, sanitizedState.waste.count - 1)
        )
        return sanitizedState
    }

    // MARK: Moves

    /// Executes the TriPeaks move (`.waste`): plays an uncovered peak card onto
    /// the waste as one scored, undoable move.
    @discardableResult
    func performTriPeaksMove(selection: Selection, to destination: Destination) -> Bool {
        guard let nextState = TriPeaksGameRules.stateByApplying(
            selection: selection,
            destination: destination,
            to: state
        ) else { return false }

        clearHint()
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .moveSelection,
                cardIDs: selection.cards.map(\.id)
            )
        )
        let previousState = state
        state = nextState
        incrementMovesCount()
        applyTriPeaksMoveScore(before: previousState, after: nextState)
        applyTimeBonusIfWon()
        self.selection = nil
        SoundManager.shared.play(.cardPlaced)
        refreshAutoFinishAvailability()
        return true
    }

    /// The n-th consecutive discard in a chain scores n; clearing a peak adds
    /// its bonus (15 for the first two, 30 for the third, which clears the
    /// board). One play removes one card, so at most one peak clears per move.
    func applyTriPeaksMoveScore(before: GameState, after: GameState) {
        applyScore(.triPeaksChainDiscard(chainLength: after.triPeaksChainLength))
        let clearedPeaks = TriPeaksGameRules.clearedPeakCount(in: after.triPeaks)
        if clearedPeaks > TriPeaksGameRules.clearedPeakCount(in: before.triPeaks) {
            applyScore(
                clearedPeaks == TriPeaksGeometry.peakCount ? .triPeaksBoardClear : .triPeaksPeakClear
            )
        }
    }

    // MARK: Interaction

    /// A TriPeaks card either plays onto the waste or it doesn't, so a tap
    /// auto-moves the card and an unplayable tap just gives failure feedback —
    /// there is no two-step select-then-tap flow.
    func handleTriPeaksTap(index: Int) {
        guard state.triPeaks.indices.contains(index),
              let card = state.triPeaks[index] else { return }
        HapticManager.shared.play(.cardPickUp)

        guard card.isFaceUp, TriPeaksGeometry.isUncovered(index, in: state.triPeaks) else {
            selection = nil
            HapticManager.shared.play(.invalidDrop)
            return
        }

        let tappedSelection = Selection(source: .triPeaks(index: index), cards: [card])
        _ = queueBestAutoMove(for: tappedSelection)
        selection = nil
    }

    @discardableResult
    func startDragFromTriPeaks(index: Int) -> Bool {
        guard state.triPeaks.indices.contains(index),
              let card = state.triPeaks[index],
              card.isFaceUp,
              TriPeaksGeometry.isUncovered(index, in: state.triPeaks) else { return false }
        clearHint()
        selection = Selection(source: .triPeaks(index: index), cards: [card])
        isDragging = true
        return true
    }

    // MARK: Stock

    /// Flips one stock card onto the waste. Single pass: once the stock is
    /// empty the slot goes dead — TriPeaks never recycles.
    func handleTriPeaksStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        guard !state.stock.isEmpty else { return }
        drawFromStock()
        applyScore(.triPeaksStockFlip)
    }
}
