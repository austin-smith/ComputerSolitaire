enum KlondikeGameRules {
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        if destinationPile.isEmpty {
            return card.rank == .king
        }
        guard let top = destinationPile.last else { return false }
        return top.isFaceUp
            && top.suit.isRed != card.suit.isRed
            && card.rank.rawValue == top.rank.rawValue - 1
    }
}
