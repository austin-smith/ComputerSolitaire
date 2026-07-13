import Foundation

enum PyramidPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.pyramid.count == PyramidGeometry.cardCount else { return false }
        guard state.tableau.isEmpty else { return false }
        // Pyramid renders no free-cell slots or foundations, so a card stranded
        // there would be invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        guard state.foundations.allSatisfy(\.isEmpty) else { return false }
        guard (0...PyramidGameRules.maxWasteRecycles).contains(state.wasteRecyclesUsed) else {
            return false
        }
        // The TriPeaks fields belong to the TriPeaks variant alone; a card
        // stranded there would be invisible here.
        guard state.triPeaks.isEmpty, state.triPeaksChainLength == 0 else { return false }
        guard state.wasteDrawCount == min(1, state.waste.count) else { return false }

        // Legal play can never remove a card while a covering card remains, so an
        // empty slot must have empty covering slots.
        for index in state.pyramid.indices where state.pyramid[index] == nil {
            if let covering = PyramidGeometry.coveringIndices(of: index),
               state.pyramid[covering.left] != nil || state.pyramid[covering.right] != nil {
                return false
            }
        }
        return true
    }
}
