import Foundation

nonisolated enum GolfGameRules {
    static let columnCount = 7
    static let columnDepth = 5
    static let dealTableauCardCount = 35
    /// 52 cards minus the 35-card board and the one-card waste starter.
    static let dealStockCardCount = 16

    /// Exactly one rank apart, suit ignored. Strict Golf never wraps, so
    /// K and A do not connect.
    static func ranksAreAdjacent(_ first: Int, _ second: Int) -> Bool {
        abs(first - second) == 1
    }

    /// Strict Golf legality on raw rank values, shared verbatim by the
    /// session rules and `GolfPlanner`: one rank up or down with no
    /// wraparound, and a waste-top King accepts nothing — it is dead until a
    /// stock flip. (A King may still be played onto a Queen; the dead-end is
    /// one-directional.)
    static func canPlayRank(_ cardRank: Int, ontoWasteTop wasteTopRank: Int) -> Bool {
        guard wasteTopRank != Rank.king.rawValue else { return false }
        return ranksAreAdjacent(cardRank, wasteTopRank)
    }

    /// Whether the exposed (last) card of `column` may play onto the waste
    /// right now.
    static func canPlay(column: Int, in state: GameState) -> Bool {
        guard state.variant == .golf,
              state.tableau.indices.contains(column),
              let card = state.tableau[column].last,
              let wasteTop = state.waste.last else { return false }
        return canPlayRank(card.rank.rawValue, ontoWasteTop: wasteTop.rank.rawValue)
    }

    /// Single source of truth for applying a Golf move; used by the session
    /// and the advisor so their outcomes can never drift. The only legal move
    /// shape is playing the exposed card of a column onto the waste. Returns
    /// nil for illegal moves.
    static func stateByApplying(
        selection: Selection,
        destination: Destination,
        to state: GameState
    ) -> GameState? {
        guard state.variant == .golf else { return nil }
        guard selection.cards.count == 1, let selectedCard = selection.cards.first else { return nil }
        guard case .tableau(let pile, let index) = selection.source,
              case .waste = destination else { return nil }
        guard state.tableau.indices.contains(pile),
              index == state.tableau[pile].count - 1,
              canPlay(column: pile, in: state),
              state.tableau[pile].last?.id == selectedCard.id else { return nil }

        var nextState = state
        nextState.tableau[pile].removeLast()
        nextState.waste.append(selectedCard)
        // The single visible waste card follows the new top.
        nextState.wasteDrawCount = 1
        return nextState
    }
}
