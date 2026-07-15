import Foundation

nonisolated enum KlondikeAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        AutoMoveAdvisor.isValidTableauSequence(cards)
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
        // Klondike has no auxiliary destination type beyond tableau/foundation.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        AutoMoveAdvisor.flipExposedFaceDownTop(on: &state, pileIndex: pileIndex)
    }

}
