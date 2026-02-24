import Foundation

struct GameState: Equatable, Codable {
    var variant: GameVariant
    var stock: [Card]
    var waste: [Card]
    var wasteDrawCount: Int
    var freeCells: [Card?]
    var foundations: [[Card]]
    var tableau: [[Card]]

    enum CodingKeys: String, CodingKey {
        case variant
        case stock
        case waste
        case wasteDrawCount
        case freeCells
        case foundations
        case tableau
    }

    init(
        variant: GameVariant = .klondike,
        stock: [Card],
        waste: [Card],
        wasteDrawCount: Int,
        freeCells: [Card?] = Array(repeating: nil, count: 4),
        foundations: [[Card]],
        tableau: [[Card]]
    ) {
        self.variant = variant
        self.stock = stock
        self.waste = waste
        self.wasteDrawCount = wasteDrawCount
        self.freeCells = freeCells
        self.foundations = foundations
        self.tableau = tableau
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variant = try container.decodeIfPresent(GameVariant.self, forKey: .variant) ?? .klondike
        stock = try container.decode([Card].self, forKey: .stock)
        waste = try container.decode([Card].self, forKey: .waste)
        wasteDrawCount = try container.decode(Int.self, forKey: .wasteDrawCount)
        freeCells = try container.decodeIfPresent([Card?].self, forKey: .freeCells)
            ?? Array(repeating: nil, count: 4)
        foundations = try container.decode([[Card]].self, forKey: .foundations)
        tableau = try container.decode([[Card]].self, forKey: .tableau)
    }

    static func newGame() -> GameState {
        newGame(variant: .klondike)
    }

    static func newGame(variant: GameVariant) -> GameState {
        switch variant {
        case .klondike:
            return newKlondikeGame()
        case .freecell:
            return newFreeCellGame()
        }
    }
}
