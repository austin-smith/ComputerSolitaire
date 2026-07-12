import Foundation

enum GameVariant: String, CaseIterable, Codable {
    case klondike
    case freecell
    case yukon
    case pyramid

    var title: String {
        switch self {
        case .klondike:
            return "Klondike"
        case .freecell:
            return "FreeCell"
        case .yukon:
            return "Yukon"
        case .pyramid:
            return "Pyramid"
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
        case .pyramid:
            return "Pair cards that total 13"
        }
    }

    var boardColumnCount: Int {
        switch self {
        case .klondike, .yukon, .pyramid:
            return 7
        case .freecell:
            return 8
        }
    }

    /// Whether deals place face-down cards in the tableau (tapping an exposed
    /// face-down top flips it).
    var dealsFaceDownTableauCards: Bool {
        switch self {
        case .klondike, .yukon:
            return true
        case .freecell, .pyramid:
            return false
        }
    }

    /// Whether the variant deals from a stock into a waste pile.
    var dealsFromStock: Bool {
        switch self {
        case .klondike, .pyramid:
            return true
        case .freecell, .yukon:
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
