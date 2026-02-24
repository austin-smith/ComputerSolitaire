enum GameRules {
    static func canMoveToFoundation(card: Card, foundation: [Card]) -> Bool {
        if foundation.isEmpty {
            return card.rank == .ace
        }
        guard let top = foundation.last else { return false }
        return top.suit == card.suit && card.rank.rawValue == top.rank.rawValue + 1
    }

    static func canMoveToTableau(
        card: Card,
        destinationPile: [Card],
        variant: GameVariant
    ) -> Bool {
        switch variant {
        case .klondike:
            return KlondikeGameRules.canMoveToTableau(card: card, destinationPile: destinationPile)
        case .freecell:
            return FreeCellGameRules.canMoveToTableau(card: card, destinationPile: destinationPile)
        }
    }

    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        KlondikeGameRules.canMoveToTableau(card: card, destinationPile: destinationPile)
    }

    static func canMoveToFreeCell(destination: Card?) -> Bool {
        FreeCellGameRules.canMoveToFreeCell(destination: destination)
    }

    static func isValidDescendingAlternatingSequence(_ cards: [Card]) -> Bool {
        SharedGameRules.isValidDescendingAlternatingSequence(cards)
    }

    static func maxFreeCellTransferCount(
        freeCellSlots: [Card?],
        tableau: [[Card]],
        destination: Destination
    ) -> Int {
        FreeCellGameRules.maxTransferCount(
            freeCellSlots: freeCellSlots,
            tableau: tableau,
            destination: destination
        )
    }
}

enum SharedGameRules {
    static func isValidDescendingAlternatingSequence(_ cards: [Card]) -> Bool {
        guard cards.count > 1 else { return true }
        for index in 0..<(cards.count - 1) {
            let upper = cards[index]
            let lower = cards[index + 1]
            guard upper.suit.isRed != lower.suit.isRed else { return false }
            guard upper.rank.rawValue == lower.rank.rawValue + 1 else { return false }
        }
        return true
    }
}
