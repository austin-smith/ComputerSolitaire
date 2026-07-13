import Foundation

enum TriPeaksGameRules {
    /// One rank above or below, suit ignored; ranks wrap, so K↔A and A↔2 both
    /// connect (difference 1 or 12 around the 13-rank cycle).
    static func ranksAdjacentWithWrap(_ first: Rank, _ second: Rank) -> Bool {
        let difference = abs(first.rawValue - second.rawValue)
        return difference == 1 || difference == Rank.allCases.count - 1
    }

    /// Whether the card at `index` may be played onto the waste right now:
    /// present, face up, uncovered, and rank-adjacent to the waste top.
    static func canPlay(index: Int, in state: GameState) -> Bool {
        guard state.variant == .tripeaks,
              state.triPeaks.indices.contains(index),
              let card = state.triPeaks[index],
              card.isFaceUp,
              TriPeaksGeometry.isUncovered(index, in: state.triPeaks),
              let wasteTop = state.waste.last else { return false }
        return ranksAdjacentWithWrap(card.rank, wasteTop.rank)
    }

    /// Single source of truth for applying a TriPeaks move; used by the session
    /// and the advisor so their outcomes can never drift. The only legal move
    /// shape is playing an uncovered peak card onto the waste. Returns nil for
    /// illegal moves.
    static func stateByApplying(
        selection: Selection,
        destination: Destination,
        to state: GameState
    ) -> GameState? {
        guard state.variant == .tripeaks else { return nil }
        guard selection.cards.count == 1, let selectedCard = selection.cards.first else { return nil }
        guard case .triPeaks(let sourceIndex) = selection.source,
              case .waste = destination else { return nil }
        guard canPlay(index: sourceIndex, in: state),
              state.triPeaks[sourceIndex]?.id == selectedCard.id else { return nil }

        var nextState = state
        nextState.triPeaks[sourceIndex] = nil
        nextState.waste.append(selectedCard)
        flipNewlyUncoveredCards(in: &nextState)
        nextState.triPeaksChainLength += 1
        // The single visible waste card follows the new top.
        nextState.wasteDrawCount = 1
        return nextState
    }

    /// A face-down card flips face up once both cards covering it are removed.
    static func flipNewlyUncoveredCards(in state: inout GameState) {
        for index in state.triPeaks.indices {
            guard var card = state.triPeaks[index],
                  !card.isFaceUp,
                  TriPeaksGeometry.isUncovered(index, in: state.triPeaks) else { continue }
            card.isFaceUp = true
            state.triPeaks[index] = card
        }
    }

    /// Apex slots cleared so far (0...3). A single play removes one card, so
    /// at most one apex clears per move; the third clear is the board clear.
    static func clearedPeakCount(in triPeaks: [Card?]) -> Int {
        TriPeaksGeometry.apexIndices.count { triPeaks[$0] == nil }
    }
}
