import Foundation

enum Suit: CaseIterable, Codable {
    case spades
    case hearts
    case diamonds
    case clubs

    var isRed: Bool {
        switch self {
        case .hearts, .diamonds:
            return true
        case .spades, .clubs:
            return false
        }
    }

    var symbolName: String {
        switch self {
        case .spades:
            return "suit.spade.fill"
        case .hearts:
            return "suit.heart.fill"
        case .diamonds:
            return "suit.diamond.fill"
        case .clubs:
            return "suit.club.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .spades: "Spades"
        case .hearts: "Hearts"
        case .diamonds: "Diamonds"
        case .clubs: "Clubs"
        }
    }
}

enum Rank: Int, CaseIterable, Comparable, Codable {
    case ace = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13

    static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .ace:
            return "A"
        case .jack:
            return "J"
        case .queen:
            return "Q"
        case .king:
            return "K"
        default:
            return String(rawValue)
        }
    }

    var accessibilityName: String {
        switch self {
        case .ace: "Ace"
        case .two: "Two"
        case .three: "Three"
        case .four: "Four"
        case .five: "Five"
        case .six: "Six"
        case .seven: "Seven"
        case .eight: "Eight"
        case .nine: "Nine"
        case .ten: "Ten"
        case .jack: "Jack"
        case .queen: "Queen"
        case .king: "King"
        }
    }
}

struct Card: Identifiable, Equatable, Codable {
    let id: UUID
    let suit: Suit
    let rank: Rank
    var isFaceUp: Bool

    init(id: UUID = UUID(), suit: Suit, rank: Rank, isFaceUp: Bool = false) {
        self.id = id
        self.suit = suit
        self.rank = rank
        self.isFaceUp = isFaceUp
    }
}

/// A card's face — suit and rank without instance identity. Deck-composition
/// checks count these; Spider's two decks carry each identity more than once.
struct CardIdentity: Hashable {
    let suit: Suit
    let rank: Rank
}

extension Card {
    var accessibilityName: String {
        guard isFaceUp else { return "Face-down card" }
        return "\(rank.accessibilityName) of \(suit.accessibilityName)"
    }

    static func fullDeck() -> [Card] {
        var deck: [Card] = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                deck.append(Card(suit: suit, rank: rank))
            }
        }
        return deck
    }
}
