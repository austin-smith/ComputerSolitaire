import Foundation

enum GameVariant: String, CaseIterable, Codable {
    case klondike
    case freecell
    case yukon
    case spider

    var title: String {
        switch self {
        case .klondike:
            return "Klondike"
        case .freecell:
            return "FreeCell"
        case .yukon:
            return "Yukon"
        case .spider:
            return "Spider"
        }
    }

    var subtitle: String {
        switch self {
        case .klondike:
            return "Classic Solitaire"
        case .freecell:
            return "Strategic open layout"
        case .yukon:
            return "Move any face-up stack"
        case .spider:
            return "Build full suit runs"
        }
    }

    var boardColumnCount: Int {
        switch self {
        case .klondike, .yukon:
            return 7
        case .freecell:
            return 8
        case .spider:
            return 10
        }
    }

    /// Whether deals place face-down cards in the tableau (tapping an exposed
    /// face-down top flips it).
    var dealsFaceDownTableauCards: Bool {
        switch self {
        case .klondike, .yukon:
            return true
        case .freecell:
            return false
        case .spider:
            return true
        }
    }

    /// How many foundation piles the variant plays with. Spider banks its
    /// eight completed King-to-Ace runs in foundations; the other variants
    /// build one foundation per suit.
    var foundationPileCount: Int {
        switch self {
        case .klondike, .freecell, .yukon:
            return 4
        case .spider:
            return 8
        }
    }

    /// How many cards a deal uses. Spider plays with two decks.
    var deckCardCount: Int {
        switch self {
        case .klondike, .freecell, .yukon:
            return 52
        case .spider:
            return 104
        }
    }

    /// Whether the player builds foundations by moving cards onto them.
    /// Spider's completed runs move to a foundation automatically, so its
    /// foundations are never a drag, drop, or tap target.
    var playerBuildsFoundations: Bool {
        switch self {
        case .klondike, .freecell, .yukon:
            return true
        case .spider:
            return false
        }
    }
}

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

/// Spider difficulty: how many distinct suits the two-deck (104-card) deal
/// is composed of.
enum SpiderSuitCount: Int, CaseIterable, Codable {
    case one = 1
    case two = 2
    case four = 4

    var title: String {
        switch self {
        case .one:
            return "1 Suit"
        case .two:
            return "2 Suits"
        case .four:
            return "4 Suits"
        }
    }
}
