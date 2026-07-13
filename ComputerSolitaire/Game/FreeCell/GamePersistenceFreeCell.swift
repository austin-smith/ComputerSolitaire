import Foundation

enum FreeCellPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 8 else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
        // The pyramid fields belong to the Pyramid variant alone; a card stranded
        // there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.wasteRecyclesUsed == 0 else {
            return false
        }
        return state.wasteDrawCount == 0
    }
}
