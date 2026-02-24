import Foundation

enum FreeCellAutoMoveAdvisor {
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

    static func destinationPriority(for destination: Destination, in state: GameState) -> Int {
        switch destination {
        case .tableau(let index):
            return state.tableau[index].isEmpty ? 0 : 2
        case .foundation:
            return 1
        case .freeCell:
            return 0
        }
    }
}
