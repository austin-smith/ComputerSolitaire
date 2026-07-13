import Foundation

extension SolitaireViewModel {
    func handleScorpionStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        dealScorpionStock()
    }

    /// Deals the three-card stock: one face-up card onto each of the first
    /// three piles, banking any runs the deal completes. Legal at any time
    /// while the stock remains, so an empty stock just ignores the tap (the
    /// stock view is also disabled then).
    func dealScorpionStock() {
        guard !state.stock.isEmpty else { return }
        let dealtCardIDs = state.stock.map(\.id)
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .dealTableauRow,
                cardIDs: dealtCardIDs
            )
        )
        let resolution = ScorpionGameRules.dealStock(in: &state) ?? ScorpionGameRules.Resolution()
        publishTableauDealEvent(dealtCardIDs: dealtCardIDs)
        incrementMovesCount()
        applyScorpionResolutionEffects(resolution)
        SoundManager.shared.play(.cardDrawFromStock)
        HapticManager.shared.play(.stockDraw)
        applyTimeBonusIfWon()
        selection = nil
        refreshAutoFinishAvailability()
    }

    /// Banks completed runs after a tableau landing, scoring each run and
    /// every reveal the banking exposed.
    func resolveCompletedScorpionRuns() {
        applyScorpionResolutionEffects(ScorpionGameRules.resolveCompletedRuns(in: &state))
    }

    private func applyScorpionResolutionEffects(_ resolution: ScorpionGameRules.Resolution) {
        guard resolution.bankedRunCount > 0 else { return }
        // A banked run exposing the face-down card beneath it is a reveal
        // like any other; the rules promise +5 for every card turned face up.
        for _ in 0..<resolution.revealedCardCount {
            applyScore(.turnOverTableauCard)
        }
        for _ in 0..<resolution.bankedRunCount {
            applyScore(.scorpionCompletedRun)
        }
        SoundManager.shared.play(.cardPlaced)
        HapticManager.shared.play(.cardFlipFaceUp)
    }
}
