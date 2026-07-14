import Foundation

nonisolated enum FortyThievesAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        // Forty Thieves' defining rule: only the exposed top card of a column
        // moves — never a sequence, however well ordered.
        cards.count == 1
    }

    static func allowsTableauTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        // Foundations are locked: a card placed there never returns to the
        // tableau. Belt and braces — `candidateSelections` never offers a
        // foundation source for a rollback-free variant.
        if case .foundation = selection.source {
            return false
        }
        return true
    }

    static func isRedundantEmptyColumnTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        // Empty columns accept any card, so relocating a lone card between
        // empty columns is a no-op no matter what it is.
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
        // Forty Thieves has no auxiliary destination type beyond tableau/foundation.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        // Every card deals (and stays) face up; nothing to flip.
    }
}
