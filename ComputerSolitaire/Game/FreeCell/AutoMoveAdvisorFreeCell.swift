import Foundation

enum FreeCellAutoMoveAdvisor {
    static func allowsTableauPickup(of cards: [Card], in state: GameState) -> Bool {
        AutoMoveAdvisor.isValidTableauSequence(cards)
    }

    static func allowsTableauTransfer(
        selection: Selection,
        destinationTableauIndex: Int,
        in state: GameState
    ) -> Bool {
        guard selection.cards.count > 1 else { return true }
        guard GameRules.isValidDescendingAlternatingSequence(selection.cards) else {
            return false
        }
        let maxTransferCount = GameRules.maxFreeCellTransferCount(
            freeCellSlots: state.freeCells,
            tableau: state.tableau,
            destination: .tableau(destinationTableauIndex)
        )
        return selection.cards.count <= maxTransferCount
    }

    static func appendAuxiliaryDestinations(
        for selection: Selection,
        in state: GameState,
        destinations: inout [Destination]
    ) {
        guard selection.cards.count == 1 else { return }
        for freeCellIndex in state.freeCells.indices {
            if case .freeCell = selection.source {
                continue
            }
            if GameRules.canMoveToFreeCell(destination: state.freeCells[freeCellIndex]) {
                destinations.append(.freeCell(freeCellIndex))
            }
        }
    }

    static func applyTableauSourceRemovalEffects(on state: inout GameState, pileIndex: Int) {
        // FreeCell has no hidden cards to reveal.
    }
}
