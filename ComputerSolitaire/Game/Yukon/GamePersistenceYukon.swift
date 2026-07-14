import Foundation

nonisolated enum YukonPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 7 else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
        // Yukon renders no free-cell slots, so a card stranded there would be
        // invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        // The pyramid and TriPeaks fields belong to those variants alone; a card
        // stranded there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.wasteRecyclesUsed == 0 else {
            return false
        }
        guard state.triPeaks.isEmpty, state.triPeaksChainLength == 0 else { return false }
        // Canfield's reserve belongs to that variant alone; a card stranded
        // there would be invisible here.
        guard state.reserve.isEmpty else { return false }
        return state.wasteDrawCount == 0
    }
}
