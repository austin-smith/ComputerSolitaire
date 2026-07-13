import Foundation

enum FortyThievesPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == FortyThievesGameRules.columnCount else { return false }
        // Every board card is dealt (and stays) face up. No depth cap: columns
        // grow past their dealt four when built on.
        guard state.tableau.allSatisfy({ $0.allSatisfy(\.isFaceUp) }) else { return false }
        // Forty Thieves renders no free-cell slots, so a card stranded there
        // would be invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        // The pyramid and TriPeaks fields belong to those variants alone; a
        // card stranded there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.triPeaks.isEmpty,
              state.triPeaksChainLength == 0, state.wasteRecyclesUsed == 0 else {
            return false
        }
        // The stock deals 64 cards and only ever shrinks, face down.
        guard state.stock.count <= FortyThievesGameRules.dealStockCardCount else { return false }
        guard state.stock.allSatisfy({ !$0.isFaceUp }) else { return false }
        guard state.waste.allSatisfy(\.isFaceUp) else { return false }
        // Draws and waste plays both leave exactly one card fanned while the
        // waste holds any; the planner's state keys rely on this invariant.
        guard state.wasteDrawCount == min(1, state.waste.count) else { return false }
        return state.foundations.allSatisfy(isValidFoundationPile)
    }

    /// A Forty Thieves foundation grows one suit from the Ace up; two
    /// foundations per suit share the two decks.
    private static func isValidFoundationPile(_ pile: [Card]) -> Bool {
        guard !pile.isEmpty else { return true }
        return SharedGameRules.isDescendingSameSuitRun(Array(pile.reversed()))
            && pile.first?.rank == .ace
    }
}
