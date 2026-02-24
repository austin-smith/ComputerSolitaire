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

extension Card {
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
