import Foundation

nonisolated struct GameState: Equatable, Codable {
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
    /// TriPeaks layout: 28 row-major slots (three apexes, then rows of 6, 9,
    /// and the 10-card base — see `TriPeaksGeometry.rowRanges`); nil means
    /// played onto the waste. Empty for the other variants.
    var triPeaks: [Card?]
    /// Consecutive TriPeaks tableau discards since the last stock flip; the
    /// n-th discard in a chain scores n. Zero for the other variants.
    var triPeaksChainLength: Int
    /// Canfield's thirteen-card reserve, bottom first; only the last card is
    /// face up and available. Empty for the other variants.
    var reserve: [Card]

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
        case triPeaks
        case triPeaksChainLength
        case reserve
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
        wasteRecyclesUsed: Int = 0,
        triPeaks: [Card?] = [],
        triPeaksChainLength: Int = 0,
        reserve: [Card] = []
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
        self.triPeaks = triPeaks
        self.triPeaksChainLength = triPeaksChainLength
        self.reserve = reserve
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
        triPeaks = try container.decodeIfPresent([Card?].self, forKey: .triPeaks) ?? []
        triPeaksChainLength = try container.decodeIfPresent(Int.self, forKey: .triPeaksChainLength) ?? 0
        reserve = try container.decodeIfPresent([Card].self, forKey: .reserve) ?? []
    }

    var isWon: Bool {
        switch variant {
        case .klondike, .freecell, .yukon, .spider, .fortyThieves, .scorpion, .canfield:
            // Won once every foundation holds a full run (Ace-to-King on the
            // build-up variants, a banked King-to-Ace run per Spider or
            // Scorpion foundation, a wrapped base-to-base run per Canfield
            // foundation).
            return foundations.allSatisfy { $0.count == Rank.allCases.count }
        case .pyramid:
            // Won once every pyramid slot is cleared; stock and waste may keep cards.
            return !pyramid.isEmpty && pyramid.allSatisfy { $0 == nil }
        case .tripeaks:
            // Won once every peak slot is cleared; stock and waste may keep cards.
            return !triPeaks.isEmpty && triPeaks.allSatisfy { $0 == nil }
        case .golf:
            // Won once every column is emptied; stock and waste may keep cards.
            return !tableau.isEmpty && tableau.allSatisfy(\.isEmpty)
        }
    }

    static func newGame() -> GameState {
        newGame(variant: .klondike)
    }

    static func newGame(variant: GameVariant, spiderSuitCount: SpiderSuitCount = .two) -> GameState {
        switch variant {
        case .klondike:
            return newKlondikeGame()
        case .freecell:
            return newFreeCellGame()
        case .yukon:
            return newYukonGame()
        case .spider:
            return newSpiderGame(suitCount: spiderSuitCount)
        case .pyramid:
            return newPyramidGame()
        case .tripeaks:
            return newTriPeaksGame()
        case .golf:
            return newGolfGame()
        case .fortyThieves:
            return newFortyThievesGame()
        case .scorpion:
            return newScorpionGame()
        case .canfield:
            return newCanfieldGame()
        }
    }
}
