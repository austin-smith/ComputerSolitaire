import Foundation

enum GameVariant: String, CaseIterable, Codable {
    case klondike
    case freecell

    var title: String {
        switch self {
        case .klondike:
            return "Klondike"
        case .freecell:
            return "FreeCell"
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
