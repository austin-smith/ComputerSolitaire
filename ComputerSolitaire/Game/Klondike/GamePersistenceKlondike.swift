import Foundation

enum KlondikePersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 7 else { return false }
        return state.wasteDrawCount >= 0 && state.wasteDrawCount <= state.waste.count
    }
}
