import Foundation

/// Spider always plays 104 cards from two decks; the difficulty decides how
/// many distinct suits compose them.
enum SpiderDeck {
    static func suits(for suitCount: SpiderSuitCount) -> [Suit] {
        switch suitCount {
        case .one:
            return [.spades]
        case .two:
            return [.spades, .hearts]
        case .four:
            return Suit.allCases
        }
    }

    static func deck(suitCount: SpiderSuitCount) -> [Card] {
        var deck: [Card] = []
        for suit in suits(for: suitCount) {
            for _ in 0..<copiesPerSuit(for: suitCount) {
                for rank in Rank.allCases {
                    deck.append(Card(suit: suit, rank: rank))
                }
            }
        }
        return deck
    }

    static func expectedIdentityCounts(suitCount: SpiderSuitCount) -> [CardIdentity: Int] {
        var counts: [CardIdentity: Int] = [:]
        for suit in suits(for: suitCount) {
            for rank in Rank.allCases {
                counts[CardIdentity(suit: suit, rank: rank)] = copiesPerSuit(for: suitCount)
            }
        }
        return counts
    }

    private static func copiesPerSuit(for suitCount: SpiderSuitCount) -> Int {
        GameVariant.spider.deckCardCount / (suits(for: suitCount).count * Rank.allCases.count)
    }
}

extension GameState {
    static func newSpiderGame(suitCount: SpiderSuitCount) -> GameState {
        var deck = SpiderDeck.deck(suitCount: suitCount).shuffled()
        var tableau = Array(repeating: [Card](), count: 10)

        for pileIndex in 0..<10 {
            let cardCount = pileIndex < 4 ? 6 : 5
            for cardIndex in 0..<cardCount {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex == cardCount - 1
                tableau[pileIndex].append(card)
            }
        }

        return GameState(
            variant: .spider,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 8),
            tableau: tableau
        )
    }

    /// The Spider difficulty this state was dealt with, derived from the suit
    /// variety of the cards in play. `nil` for other variants.
    var spiderSuitCount: SpiderSuitCount? {
        guard variant == .spider else { return nil }
        let suits = Set((stock + foundations.joined() + tableau.joined()).map(\.suit))
        return SpiderSuitCount(rawValue: suits.count)
    }
}
