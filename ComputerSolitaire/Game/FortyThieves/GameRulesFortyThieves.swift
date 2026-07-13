import Foundation

enum FortyThievesGameRules {
    static let columnCount = 10
    static let dealColumnDepth = 4
    static let dealTableauCardCount = 40
    /// The 104-card two-deck deal minus the 40-card board.
    static let dealStockCardCount = 64

    /// Tableau landing rule: an empty column takes any single card; otherwise
    /// the moving card goes on the top card of the same suit, one rank higher.
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        guard let top = destinationPile.last else { return true }
        return top.suit == card.suit && card.rank.rawValue == top.rank.rawValue - 1
    }

    /// Whether sending `card` to a foundation can never cost the game. Forty
    /// Thieves foundations are locked, so an eager send is irrevocable — but
    /// with two decks and same-suit building, only same-suit cards ever need
    /// `card` as a tableau landing spot. Aces and twos are always safe; rank r
    /// is safe once both foundations of its suit have reached r − 2, because
    /// from then on every same-suit card that could want to land on `card` is
    /// directly foundation-playable instead.
    static func isSafeFoundationMove(card: Card, in state: GameState) -> Bool {
        let rank = card.rank.rawValue
        if rank <= 2 { return true }
        let sameSuitTopRanks = state.foundations
            .filter { $0.first?.suit == card.suit }
            .map { $0.last?.rank.rawValue ?? 0 }
        guard sameSuitTopRanks.count == 2 else { return false }
        return sameSuitTopRanks.allSatisfy { $0 >= rank - 2 }
    }
}
