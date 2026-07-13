import Foundation

enum KlondikePersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 7 else { return false }
        // Klondike renders no free-cell slots, so a card stranded there would be
        // invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        // The pyramid fields belong to the Pyramid variant alone; a card stranded
        // there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.wasteRecyclesUsed == 0 else {
            return false
        }
        return state.wasteDrawCount >= 0 && state.wasteDrawCount <= state.waste.count
    }
}
