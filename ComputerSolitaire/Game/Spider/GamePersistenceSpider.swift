import Foundation

enum SpiderPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 10 else { return false }
        // The stock only ever shrinks by full ten-card rows.
        guard state.stock.count.isMultiple(of: 10), state.stock.count <= 50 else { return false }
        guard state.stock.allSatisfy({ !$0.isFaceUp }) else { return false }
        guard state.waste.isEmpty else { return false }
        // Spider renders no free-cell slots, so a card stranded there would be
        // invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        // The pyramid and TriPeaks fields belong to those variants alone; a card
        // stranded there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.wasteRecyclesUsed == 0 else {
            return false
        }
        guard state.triPeaks.isEmpty, state.triPeaksChainLength == 0 else { return false }
        guard state.wasteDrawCount == 0 else { return false }
        return state.foundations.allSatisfy(isValidFoundationPile)
    }

    /// A Spider foundation is empty until a run completes, then holds exactly
    /// one banked run: thirteen same-suit cards, Ace at the bottom.
    private static func isValidFoundationPile(_ pile: [Card]) -> Bool {
        guard !pile.isEmpty else { return true }
        guard pile.count == Rank.allCases.count else { return false }
        return SharedGameRules.isDescendingSameSuitRun(Array(pile.reversed()))
    }
}
