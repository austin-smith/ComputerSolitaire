import Foundation

nonisolated enum CanfieldAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        // Canfield's defining transfer rule: a pile moves between tableau
        // piles only in its entirety, and its exposed top card plays to a
        // foundation. Anything between — a sequence lifted off the middle of
        // a pile — never moves, so only those two pickups exist.
        guard let first = cards.first else { return false }
        if cards.count == 1 { return true }
        guard CanfieldGameRules.isPackedSequence(cards) else { return false }
        return state.tableau.contains { pile in
            pile.first?.id == first.id && pile.count == cards.count
        }
    }

    static func allowsTableauTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        guard state.tableau.indices.contains(destinationTableauIndex) else { return false }
        return CanfieldGameRules.allowsTableauTransfer(
            selection: selection,
            destinationPile: state.tableau[destinationTableauIndex],
            in: state
        )
    }

    static func isRedundantEmptyColumnTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        // The only selection that may take a space is the top waste card, and
        // playing it there is real progress; tableau piles never target
        // spaces, so the whole-pile shuffle the other variants filter out
        // cannot arise.
        false
    }

    static func appendAuxiliaryDestinations(
        for selection: Selection,
        in state: GameState,
        destinations: inout [Destination]
    ) {
        // Canfield has no auxiliary destination type beyond tableau/foundation.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        // The compulsory fill: an emptied pile takes the reserve's exposed
        // card at once, so spaces only ever persist after the reserve is out.
        CanfieldGameRules.refillEmptyPileFromReserve(on: &state, pileIndex: pileIndex)
    }
}
