import Foundation

nonisolated enum CanfieldPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == CanfieldGameRules.tableauPileCount else { return false }
        // Every tableau card deals (and stays) face up, and every pile stays a
        // packed run — the rules only ever land legal builds and whole piles.
        guard state.tableau.allSatisfy({ pile in
            pile.isEmpty || CanfieldGameRules.isPackedSequence(pile)
        }) else { return false }
        // The compulsory fill: a space can only persist once the reserve is out.
        guard state.reserve.isEmpty || state.tableau.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        // The reserve deals thirteen and only ever shrinks; exactly its top
        // card is face up.
        guard state.reserve.count <= CanfieldGameRules.reserveCardCount else { return false }
        guard state.reserve.enumerated().allSatisfy({ index, card in
            card.isFaceUp == (index == state.reserve.count - 1)
        }) else { return false }
        // Canfield renders no free-cell slots, so a card stranded there would
        // be invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        // The pyramid and TriPeaks fields belong to those variants alone; a
        // card stranded there would be invisible here. Recycles are unlimited
        // and deliberately untracked.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.triPeaks.isEmpty,
              state.triPeaksChainLength == 0, state.wasteRecyclesUsed == 0 else {
            return false
        }
        guard state.stock.count <= CanfieldGameRules.dealStockCardCount else { return false }
        guard state.stock.allSatisfy({ !$0.isFaceUp }) else { return false }
        guard state.waste.allSatisfy(\.isFaceUp) else { return false }
        // The deal seeds the base card before play and foundations are locked,
        // so the base rank must be on the board and every foundation must be a
        // wrapped same-suit run rising from it.
        guard let baseRank = CanfieldGameRules.baseRank(in: state) else { return false }
        return state.foundations.allSatisfy { pile in
            isValidFoundationPile(pile, baseRank: baseRank)
        }
    }

    /// A Canfield foundation grows one suit upward from the base rank, turning
    /// the corner from King to Ace, to at most thirteen cards.
    private static func isValidFoundationPile(_ pile: [Card], baseRank: Rank) -> Bool {
        guard !pile.isEmpty else { return true }
        guard pile.count <= Rank.allCases.count else { return false }
        guard let suit = pile.first?.suit else { return false }
        return pile.enumerated().allSatisfy { index, card in
            card.isFaceUp
                && card.suit == suit
                && CanfieldGameRules.foundationOffset(of: card.rank, from: baseRank) == index
        }
    }
}
