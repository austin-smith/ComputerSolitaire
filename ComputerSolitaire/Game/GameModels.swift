import Foundation

enum DrawMode: Int, CaseIterable, Codable {
    case one = 1
    case three = 3

    var title: String {
        switch self {
        case .one:
            return "1-card"
        case .three:
            return "3-card"
        }
    }
}

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

struct GameState: Equatable, Codable {
    var stock: [Card]
    var waste: [Card]
    var wasteDrawCount: Int
    var foundations: [[Card]]
    var tableau: [[Card]]

    static func newGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau = Array(repeating: [Card](), count: 7)

        for pileIndex in 0..<7 {
            for cardIndex in 0...pileIndex {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex == pileIndex
                tableau[pileIndex].append(card)
            }
        }

        return GameState(
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
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

struct Selection: Equatable {
    enum Source: Equatable {
        case waste
        case foundation(pile: Int)
        case tableau(pile: Int, index: Int)
    }

    let source: Source
    let cards: [Card]
}

enum Destination: Equatable {
    case foundation(Int)
    case tableau(Int)
}

struct GameSnapshot: Codable {
    let state: GameState
    let movesCount: Int
    let undoContext: UndoAnimationContext?
}

struct UndoAnimationContext: Codable {
    enum Action: String, Codable {
        case moveSelection
        case drawFromStock
        case recycleWaste
        case flipTableauTop
    }

    let action: Action
    let cardIDs: [UUID]
}
