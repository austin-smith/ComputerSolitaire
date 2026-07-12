import Foundation

enum GameVariant: String, CaseIterable, Codable {
    case klondike
    case freecell
    case yukon

    var title: String {
        switch self {
        case .klondike:
            return "Klondike"
        case .freecell:
            return "FreeCell"
        case .yukon:
            return "Yukon"
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
        }
    }

    var boardColumnCount: Int {
        switch self {
        case .klondike, .yukon:
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
        case .freecell:
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
