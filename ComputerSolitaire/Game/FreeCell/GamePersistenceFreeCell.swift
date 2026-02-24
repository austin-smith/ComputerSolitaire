import Foundation

enum FreeCellPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 8 else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
        return state.wasteDrawCount == 0
    }
}
