import Foundation

/// Cases are declared in presentation order — most-played game types first —
/// and every list in the app (picker, menus, statistics) follows it. Slot new
/// variants by how widely played they are, not at the end.
nonisolated enum GameVariant: String, CaseIterable, Codable {
    case klondike
    case spider
    case freecell
    case pyramid
    case tripeaks
    case golf
    case yukon
    case scorpion
    case fortyThieves = "fortythieves"
    case canfield

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
        case .pyramid:
            return "Pyramid"
        case .tripeaks:
            return "TriPeaks"
        case .golf:
            return "Golf"
        case .fortyThieves:
            return "Forty Thieves"
        case .scorpion:
            return "Scorpion"
        case .canfield:
            return "Canfield"
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
        case .pyramid:
            return "Pair cards that total 13"
        case .tripeaks:
            return "Chain up or down the ranks"
        case .golf:
            return "Play one rank up or down"
        case .fortyThieves:
            return "Two decks, build down by suit"
        case .scorpion:
            return "Untangle runs suit by suit"
        case .canfield:
            return "Drain the 13-card reserve"
        }
    }

    /// How many card-widths the board lays out. Canfield's tableau is only
    /// four piles, but its top row (stock, waste, reserve, four foundations)
    /// spans seven slots, so the board sizes cards for seven columns.
    var boardColumnCount: Int {
        switch self {
        case .klondike, .yukon, .pyramid, .golf, .scorpion, .canfield:
            return 7
        case .freecell:
            return 8
        case .spider, .tripeaks, .fortyThieves:
            return 10
        }
    }

    /// Whether deals place face-down cards in the tableau (tapping an exposed
    /// face-down top flips it). TriPeaks deals face-down peak cards, but they
    /// flip automatically once uncovered — never by tapping.
    var dealsFaceDownTableauCards: Bool {
        switch self {
        case .klondike, .yukon, .spider, .scorpion:
            return true
        case .freecell, .pyramid, .tripeaks, .golf, .fortyThieves, .canfield:
            return false
        }
    }

    /// Whether the variant deals from a stock into a waste pile. Spider and
    /// Scorpion have stocks but deal them onto the tableau, never into a waste.
    var dealsFromStock: Bool {
        switch self {
        case .klondike, .pyramid, .tripeaks, .golf, .fortyThieves, .canfield:
            return true
        case .freecell, .yukon, .spider, .scorpion:
            return false
        }
    }

    /// How many foundation piles the variant plays with. Spider banks its
    /// eight completed King-to-Ace runs in foundations and Scorpion its four,
    /// Forty Thieves builds two foundations per suit from its two decks; the
    /// other variants build one foundation per suit.
    var foundationPileCount: Int {
        switch self {
        case .klondike, .freecell, .yukon, .pyramid, .tripeaks, .golf, .scorpion, .canfield:
            return 4
        case .spider, .fortyThieves:
            return 8
        }
    }

    /// How many cards a deal uses. Spider and Forty Thieves play with two decks.
    var deckCardCount: Int {
        switch self {
        case .klondike, .freecell, .yukon, .pyramid, .tripeaks, .golf, .scorpion, .canfield:
            return 52
        case .spider, .fortyThieves:
            return 104
        }
    }

    /// Whether the player builds foundations by moving cards onto them.
    /// Spider's and Scorpion's completed runs move to a foundation
    /// automatically, and Pyramid's, TriPeaks', and Golf's foundations stay
    /// empty (their removed cards go to the discard and waste respectively),
    /// so none of them treats foundations as a drag, drop, or tap target.
    var playerBuildsFoundations: Bool {
        switch self {
        case .klondike, .freecell, .yukon, .fortyThieves, .canfield:
            return true
        case .spider, .pyramid, .tripeaks, .golf, .scorpion:
            return false
        }
    }

    /// Whether a card already on a foundation may be picked back up (a scored
    /// rollback in Klondike, FreeCell, and Yukon). Forty Thieves and Canfield
    /// build their foundations but lock them: a placed card never returns to
    /// play. The variants that never build foundations have nothing to roll
    /// back.
    var allowsFoundationRollback: Bool {
        switch self {
        case .klondike, .freecell, .yukon:
            return true
        case .spider, .pyramid, .tripeaks, .golf, .fortyThieves, .scorpion, .canfield:
            return false
        }
    }

    /// Golf keeps a stroke-style score: lower is better, the win adds no time
    /// bonus, the floor-0 clamp does not apply (clearing the board subtracts
    /// one point per leftover stock card, so negative finals are the best
    /// results), and statistics track the lowest final score instead of the
    /// highest.
    var lowerScoreIsBetter: Bool {
        self == .golf
    }
}

nonisolated enum DrawMode: Int, CaseIterable, Codable {
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
nonisolated enum SpiderSuitCount: Int, CaseIterable, Codable {
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
