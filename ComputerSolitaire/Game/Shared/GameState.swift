import Foundation

struct GameState: Equatable, Codable {
    var variant: GameVariant
    var stock: [Card]
    var waste: [Card]
    var wasteDrawCount: Int
    var freeCells: [Card?]
    var foundations: [[Card]]
    var tableau: [[Card]]
    /// Pyramid layout: 28 row-major slots (row r occupies indices
    /// r(r+1)/2 ..< (r+1)(r+2)/2); nil means removed. Empty for the other variants.
    var pyramid: [Card?]
    /// Cards removed from play in Pyramid (pairs and Kings). Empty for the other variants.
    var discard: [Card]
    /// Completed waste-to-stock recycles; Pyramid allows
    /// `PyramidGameRules.maxWasteRecycles`. Zero for the other variants.
    var wasteRecyclesUsed: Int

    enum CodingKeys: String, CodingKey {
        case variant
        case stock
        case waste
        case wasteDrawCount
        case freeCells
        case foundations
        case tableau
        case pyramid
        case discard
        case wasteRecyclesUsed
    }

    init(
        variant: GameVariant = .klondike,
        stock: [Card],
        waste: [Card],
        wasteDrawCount: Int,
        freeCells: [Card?] = Array(repeating: nil, count: 4),
        foundations: [[Card]],
        tableau: [[Card]],
        pyramid: [Card?] = [],
        discard: [Card] = [],
        wasteRecyclesUsed: Int = 0
    ) {
        self.variant = variant
        self.stock = stock
        self.waste = waste
        self.wasteDrawCount = wasteDrawCount
        self.freeCells = freeCells
        self.foundations = foundations
        self.tableau = tableau
        self.pyramid = pyramid
        self.discard = discard
        self.wasteRecyclesUsed = wasteRecyclesUsed
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
        pyramid = try container.decodeIfPresent([Card?].self, forKey: .pyramid) ?? []
        discard = try container.decodeIfPresent([Card].self, forKey: .discard) ?? []
        wasteRecyclesUsed = try container.decodeIfPresent(Int.self, forKey: .wasteRecyclesUsed) ?? 0
    }

    var isWon: Bool {
        switch variant {
        case .klondike, .freecell, .yukon:
            // Won once every foundation holds a full Ace-to-King run.
            return foundations.allSatisfy { $0.count == Rank.allCases.count }
        case .pyramid:
            // Won once every pyramid slot is cleared; stock and waste may keep cards.
            return !pyramid.isEmpty && pyramid.allSatisfy { $0 == nil }
        }
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
        case .yukon:
            return newYukonGame()
        case .pyramid:
            return newPyramidGame()
        }
    }
}
