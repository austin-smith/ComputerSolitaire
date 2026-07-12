import Foundation

enum SpiderAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        // Spider's defining rule: a group moves only as a face-up
        // single-suit descending run.
        SharedGameRules.isDescendingSameSuitRun(cards)
    }

    static func allowsTableauTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        true
    }

    static func isRedundantEmptyColumnTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        // Spider's empty piles accept any leading rank, so relocating a whole
        // pile is a no-op no matter what leads it.
        AutoMoveAdvisor.isRedundantWholePileTransfer(
            selection: selection,
            destinationTableauIndex: destinationTableauIndex,
            in: state
        )
    }

    static func appendAuxiliaryDestinations(
        for selection: Selection,
        in state: GameState,
        destinations: inout [Destination]
    ) {
        // Spider has no auxiliary destination type; completed runs bank
        // themselves.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        AutoMoveAdvisor.flipExposedFaceDownTop(on: &state, pileIndex: pileIndex)
    }

    static func applyTableauDestinationEffects(on state: inout GameState, pileIndex: Int) {
        SpiderGameRules.resolveCompletedRuns(in: &state)
    }
}
