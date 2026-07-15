nonisolated enum KlondikeGameRules {
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        SharedGameRules.canMoveToKingAnchoredTableau(card: card, destinationPile: destinationPile)
    }
}
