import Foundation

nonisolated enum YukonAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        // Yukon's defining rule: any face-up card can be picked up together with
        // every card above it, regardless of whether they form a sequence.
        true
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
        AutoMoveAdvisor.isRedundantWholePileKingTransfer(
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
        // Yukon has no auxiliary destination type beyond tableau/foundation.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        AutoMoveAdvisor.flipExposedFaceDownTop(on: &state, pileIndex: pileIndex)
    }
}
