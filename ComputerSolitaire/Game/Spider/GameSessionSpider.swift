import Foundation

extension SolitaireViewModel {
    func configureSpiderNewGame() {
        configureWastelessNewGame()
        setInitialScore(Scoring.spiderInitialScore)
    }

    func configureSpiderRedeal() {
        configureWastelessRedeal()
        setInitialScore(Scoring.spiderInitialScore)
    }

    func handleSpiderStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        dealSpiderStockRow()
    }

    /// Deals the next stock row: one face-up card onto every pile, banking any
    /// runs the deal completes. Blocked while a pile is empty, with the
    /// standard invalid feedback so the tap explains itself.
    func dealSpiderStockRow() {
        guard !state.stock.isEmpty else { return }
        guard SpiderGameRules.canDealFromStock(state: state) else {
            SoundManager.shared.play(.invalidDrop)
            HapticManager.shared.play(.invalidDrop)
            return
        }
        let dealtCardIDs = state.stock.suffix(state.tableau.count).map(\.id)
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .dealTableauRow,
                cardIDs: dealtCardIDs
            )
        )
        let completedRunCount = SpiderGameRules.dealStockRow(in: &state) ?? 0
        publishTableauDealEvent(dealtCardIDs: dealtCardIDs)
        incrementMovesCount()
        applyScore(.spiderMove)
        applyCompletedSpiderRunEffects(count: completedRunCount)
        SoundManager.shared.play(.cardDrawFromStock)
        HapticManager.shared.play(.stockDraw)
        applyTimeBonusIfWon()
        selection = nil
        refreshAutoFinishAvailability()
    }

    func applySpiderMoveScore(for source: Selection.Source, destination: Destination) {
        // Classic Spider scoring: every card move costs one point.
        applyScore(.spiderMove)
    }

    /// Banks completed runs after a tableau landing, scoring each.
    func resolveCompletedSpiderRuns() {
        let completedRunCount = SpiderGameRules.resolveCompletedRuns(in: &state)
        applyCompletedSpiderRunEffects(count: completedRunCount)
    }

    private func applyCompletedSpiderRunEffects(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            applyScore(.spiderCompletedRun)
        }
        SoundManager.shared.play(.cardPlaced)
        HapticManager.shared.play(.cardFlipFaceUp)
    }
}
