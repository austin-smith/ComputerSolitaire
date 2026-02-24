import Foundation

enum KlondikeAutoMoveAdvisor {
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
        guard case .tableau(let sourcePile, let sourceIndex) = selection.source else { return false }
        guard sourcePile != destinationTableauIndex else { return false }
        guard state.tableau.indices.contains(sourcePile),
              state.tableau.indices.contains(destinationTableauIndex) else { return false }
        guard state.tableau[destinationTableauIndex].isEmpty else { return false }
        guard sourceIndex == 0 else { return false }

        let sourceCards = state.tableau[sourcePile]
        guard selection.cards.count == sourceCards.count else { return false }
        guard let movingCard = selection.cards.first else { return false }

        // Moving an entire king-led tableau stack to another empty column is a no-op
        // for advisor quality purposes (manual play can still do this).
        return movingCard.rank == .king
    }

    static func appendAuxiliaryDestinations(
        for selection: Selection,
        in state: GameState,
        destinations: inout [Destination]
    ) {
        // Klondike has no auxiliary destination type beyond tableau/foundation.
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        guard let topIndex = state.tableau[pileIndex].indices.last,
              !state.tableau[pileIndex][topIndex].isFaceUp else {
            return
        }
        state.tableau[pileIndex][topIndex].isFaceUp = true
    }

    static func revealsFaceDownCard(selection: Selection, in state: GameState) -> Bool {
        guard case .tableau(let pile, let index) = selection.source else { return false }
        guard index > 0 else { return false }
        return !state.tableau[pile][index - 1].isFaceUp
    }

    static func destinationPriority(for destination: Destination, in state: GameState) -> Int {
        switch destination {
        case .tableau(let index):
            return state.tableau[index].isEmpty ? 0 : 2
        case .foundation:
            return 1
        case .freeCell:
            return -1
        }
    }
}
