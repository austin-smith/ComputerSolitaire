enum GameRules {
    static func canMoveToFoundation(card: Card, foundation: [Card]) -> Bool {
        if foundation.isEmpty {
            return card.rank == .ace
        }
        guard let top = foundation.last else { return false }
        return top.suit == card.suit && card.rank.rawValue == top.rank.rawValue + 1
    }

    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        if destinationPile.isEmpty {
            return card.rank == .king
        }
        guard let top = destinationPile.last else { return false }
        return top.isFaceUp && top.suit.isRed != card.suit.isRed && card.rank.rawValue == top.rank.rawValue - 1
    }
}
