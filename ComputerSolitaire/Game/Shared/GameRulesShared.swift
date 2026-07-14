nonisolated enum GameRules {
    /// The Ace-anchored foundation rule shared by every variant except
    /// Canfield, whose foundations start at a dealt base rank; state-aware
    /// callers should prefer `canMoveToFoundation(card:foundation:in:)`.
    static func canMoveToFoundation(card: Card, foundation: [Card]) -> Bool {
        if foundation.isEmpty {
            return card.rank == .ace
        }
        guard let top = foundation.last else { return false }
        return top.suit == card.suit && card.rank.rawValue == top.rank.rawValue + 1
    }

    static func canMoveToFoundation(card: Card, foundation: [Card], in state: GameState) -> Bool {
        switch state.variant {
        case .klondike, .freecell, .yukon, .spider, .pyramid, .tripeaks, .golf, .fortyThieves,
             .scorpion:
            return canMoveToFoundation(card: card, foundation: foundation)
        case .canfield:
            return CanfieldGameRules.canMoveToFoundation(
                card: card,
                foundation: foundation,
                in: state
            )
        }
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
        case .yukon:
            return YukonGameRules.canMoveToTableau(card: card, destinationPile: destinationPile)
        case .spider:
            return SpiderGameRules.canMoveToTableau(card: card, destinationPile: destinationPile)
        case .scorpion:
            return ScorpionGameRules.canMoveToTableau(card: card, destinationPile: destinationPile)
        case .pyramid, .tripeaks:
            // Neither has tableau piles; their moves flow through
            // PyramidGameRules and TriPeaksGameRules.
            return false
        case .golf:
            // Golf columns are never a destination; its one move flows
            // through GolfGameRules.
            return false
        case .fortyThieves:
            return FortyThievesGameRules.canMoveToTableau(
                card: card,
                destinationPile: destinationPile
            )
        case .canfield:
            return CanfieldGameRules.canMoveToTableau(
                card: card,
                destinationPile: destinationPile
            )
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

nonisolated enum SharedGameRules {
    /// Tableau landing rule shared by Klondike and Yukon: empty piles take Kings
    /// only; otherwise the moving card goes on a face-up top of the opposite color,
    /// one rank higher.
    static func canMoveToKingAnchoredTableau(card: Card, destinationPile: [Card]) -> Bool {
        if destinationPile.isEmpty {
            return card.rank == .king
        }
        guard let top = destinationPile.last else { return false }
        return top.isFaceUp
            && top.suit.isRed != card.suit.isRed
            && card.rank.rawValue == top.rank.rawValue - 1
    }

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

    /// A face-up single-suit run descending one rank per step — Spider's movable
    /// group, and (at thirteen cards led by a King) its completed run.
    static func isDescendingSameSuitRun(_ cards: [Card]) -> Bool {
        guard !cards.isEmpty else { return false }
        guard cards.allSatisfy(\.isFaceUp) else { return false }
        for index in 0..<(cards.count - 1) {
            let upper = cards[index]
            let lower = cards[index + 1]
            guard upper.suit == lower.suit else { return false }
            guard upper.rank.rawValue == lower.rank.rawValue + 1 else { return false }
        }
        return true
    }
}
