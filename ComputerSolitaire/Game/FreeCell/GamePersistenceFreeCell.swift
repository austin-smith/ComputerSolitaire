import Foundation

nonisolated enum FreeCellPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 8 else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
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
