import Foundation

nonisolated enum ScorpionPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == 7 else { return false }
        // The stock deals exactly once, wholesale: three cards or none.
        guard state.stock.count == 3 || state.stock.isEmpty else { return false }
        guard state.stock.allSatisfy({ !$0.isFaceUp }) else { return false }
        guard state.waste.isEmpty else { return false }
        // Scorpion renders no free-cell slots, so a card stranded there would
        // be invisible and the game unwinnable.
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
        guard state.wasteDrawCount == 0 else { return false }
        return state.foundations.allSatisfy(isValidFoundationPile)
    }

    /// A Scorpion foundation is empty until a run completes, then holds exactly
    /// one banked run: thirteen same-suit cards, Ace at the bottom.
    private static func isValidFoundationPile(_ pile: [Card]) -> Bool {
        guard !pile.isEmpty else { return true }
        guard pile.count == Rank.allCases.count else { return false }
        return SharedGameRules.isDescendingSameSuitRun(Array(pile.reversed()))
    }
}
