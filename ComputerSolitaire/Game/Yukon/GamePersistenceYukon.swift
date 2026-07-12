import Foundation

enum YukonPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 7 else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
        // Yukon renders no free-cell slots, so a card stranded there would be
        // invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        return state.wasteDrawCount == 0
    }
}
