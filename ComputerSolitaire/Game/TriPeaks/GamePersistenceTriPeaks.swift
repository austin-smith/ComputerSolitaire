import Foundation

enum TriPeaksPersistenceRules {
    static func hasValidLayout(state: GameState) -> Bool {
        guard state.triPeaks.count == TriPeaksGeometry.cardCount else { return false }
        guard state.tableau.isEmpty else { return false }
        // TriPeaks renders no free-cell slots or foundations, so a card stranded
        // there would be invisible and the game unwinnable.
        guard state.freeCells.allSatisfy({ $0 == nil }) else { return false }
        guard state.foundations.allSatisfy(\.isEmpty) else { return false }
        // The pyramid fields belong to the Pyramid variant alone; a card stranded
        // there would be invisible here.
        guard state.pyramid.isEmpty, state.discard.isEmpty, state.wasteRecyclesUsed == 0 else {
            return false
        }
        // Canfield's reserve belongs to that variant alone; a card stranded
        // there would be invisible here.
        guard state.reserve.isEmpty else { return false }
        // The deal starts the waste with one card and the waste only grows, so
        // an empty waste is corrupt (there would be no match target).
        guard !state.waste.isEmpty else { return false }
        guard state.wasteDrawCount == 1 else { return false }

        // Legal play can never remove a card while a covering card remains, so an
        // empty slot must have empty covering slots.
        for index in state.triPeaks.indices where state.triPeaks[index] == nil {
            if let covering = TriPeaksGeometry.coveringIndices(of: index),
               state.triPeaks[covering.left] != nil || state.triPeaks[covering.right] != nil {
                return false
            }
        }

        // The rules flip a card the instant it is uncovered, so every present
        // card must be face up exactly when uncovered.
        for index in state.triPeaks.indices {
            guard let card = state.triPeaks[index] else { continue }
            guard card.isFaceUp == TriPeaksGeometry.isUncovered(index, in: state.triPeaks) else {
                return false
            }
        }

        // Chain cards are consecutive discards: all in the waste beyond the
        // deal's starter, and never more than the cards removed from the board.
        let removedCount = state.triPeaks.count { $0 == nil }
        return (0...min(state.waste.count - 1, removedCount)).contains(state.triPeaksChainLength)
    }
}
