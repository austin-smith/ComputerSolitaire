import Foundation

enum GolfPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.tableau.count == GolfGameRules.columnCount else { return false }
        // Columns deal five cards and only ever shrink; every board card is
        // dealt (and stays) face up.
        guard state.tableau.allSatisfy({ $0.count <= GolfGameRules.columnDepth }) else {
            return false
        }
        guard state.tableau.allSatisfy({ $0.allSatisfy(\.isFaceUp) }) else { return false }
        // Golf renders no free-cell slots or foundations, so a card stranded
        // there would be invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        guard state.foundations.allSatisfy(\.isEmpty) else { return false }
        // The pyramid and TriPeaks fields belong to those variants alone; a
        // card stranded there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.triPeaks.isEmpty,
              state.wasteRecyclesUsed == 0 else {
            return false
        }
        // Canfield's reserve belongs to that variant alone; a card stranded
        // there would be invisible here.
        guard state.reserve.isEmpty else { return false }
        // The deal starts the waste with one card and the waste only grows, so
        // an empty waste is corrupt (there would be no match target).
        guard !state.waste.isEmpty else { return false }
        guard state.wasteDrawCount == 1 else { return false }
        // The stock deals sixteen cards and only ever shrinks, face down.
        guard state.stock.count <= GolfGameRules.dealStockCardCount else { return false }
        guard state.stock.allSatisfy({ !$0.isFaceUp }) else { return false }
        return true
    }
}
