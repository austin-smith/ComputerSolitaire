import Foundation
import XCTest
@testable import Computer_Solitaire

@MainActor
enum TestCards {
    static func make(
        _ suit: Suit,
        _ rank: Rank,
        isFaceUp: Bool = true,
        id: UUID = UUID()
    ) -> Card {
        Card(id: id, suit: suit, rank: rank, isFaceUp: isFaceUp)
    }

    static func fullDeck(faceUp: Bool = false) -> [Card] {
        Suit.allCases.flatMap { suit in
            Rank.allCases.map { rank in
                Card(suit: suit, rank: rank, isFaceUp: faceUp)
            }
        }
    }
}

/// Deterministic RNG (SplitMix64) so test deals are reproducible across runs and machines.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}

@MainActor
enum GameStateFixtures {
    /// A reproducible FreeCell deal. Uses a hand-rolled Fisher–Yates so the layout for a
    /// given seed never shifts underneath the tests.
    static func seededFreeCellDeal(seed: UInt64) -> GameState {
        let deck = seededDeck(seed: seed, faceUp: true)
        var tableau = Array(repeating: [Card](), count: 8)
        for index in 0..<deck.count {
            tableau[index % 8].append(deck[index])
        }
        return GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    /// A reproducible Klondike deal matching the shape of `GameState.newKlondikeGame`.
    static func seededKlondikeDeal(seed: UInt64) -> GameState {
        var deck = seededDeck(seed: seed, faceUp: false)
        var tableau: [[Card]] = Array(repeating: [], count: 7)
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

    /// A reproducible Spider deal matching the shape of `GameState.newSpiderGame`.
    /// Mirrored by the hint probe's `seededSpiderDeal` so seeds are comparable.
    static func seededSpiderDeal(seed: UInt64, suitCount: SpiderSuitCount) -> GameState {
        var deck = seededShuffle(SpiderDeck.deck(suitCount: suitCount), seed: seed)
        var tableau: [[Card]] = Array(repeating: [], count: 10)
        for pileIndex in 0..<10 {
            let cardCount = pileIndex < 4 ? 6 : 5
            for cardIndex in 0..<cardCount {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex == cardCount - 1
                tableau[pileIndex].append(card)
            }
        }
        return GameState(
            variant: .spider,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 8),
            tableau: tableau
        )
    }

    /// A reproducible Yukon deal matching the shape of `GameState.newYukonGame`.
    static func seededYukonDeal(seed: UInt64) -> GameState {
        var deck = seededDeck(seed: seed, faceUp: false)
        var tableau: [[Card]] = Array(repeating: [], count: 7)
        for pileIndex in 0..<7 {
            let faceDownCount = pileIndex == 0 ? 0 : pileIndex
            let faceUpCount = pileIndex == 0 ? 1 : 5
            for cardIndex in 0..<(faceDownCount + faceUpCount) {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex >= faceDownCount
                tableau[pileIndex].append(card)
            }
        }
        return GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    /// A reproducible Scorpion deal matching the shape of `GameState.newScorpionGame`.
    /// Mirrored by the hint probe's `seededScorpionDeal` so seeds are comparable.
    static func seededScorpionDeal(seed: UInt64) -> GameState {
        var deck = seededDeck(seed: seed, faceUp: false)
        var tableau: [[Card]] = Array(repeating: [], count: 7)
        for pileIndex in 0..<7 {
            let faceDownCount = pileIndex < 4 ? 3 : 0
            for cardIndex in 0..<7 {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex >= faceDownCount
                tableau[pileIndex].append(card)
            }
        }
        return GameState(
            variant: .scorpion,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    /// A reproducible Pyramid deal matching the shape of `GameState.newPyramidGame`.
    static func seededPyramidDeal(seed: UInt64) -> GameState {
        var deck = seededDeck(seed: seed, faceUp: false)
        var pyramid: [Card?] = []
        for _ in 0..<PyramidGeometry.cardCount {
            var card = deck.removeLast()
            card.isFaceUp = true
            pyramid.append(card)
        }
        return GameState(
            variant: .pyramid,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            pyramid: pyramid,
            discard: []
        )
    }

    /// Hand-constructed Pyramid position for rules and planner tests. `slots` fills
    /// the pyramid top-down (nil = removed) and is padded with removed slots; any
    /// cards not on the board, in the stock, or in the waste land on the discard so
    /// persistence-facing tests still see 52 cards.
    /// A reproducible TriPeaks deal matching the shape of `GameState.newTriPeaksGame`.
    /// Mirrored by the hint probe's `seededTriPeaksDeal` so seeds are comparable.
    static func seededTriPeaksDeal(seed: UInt64) -> GameState {
        var deck = seededDeck(seed: seed, faceUp: false)
        var triPeaks: [Card?] = []
        for index in 0..<TriPeaksGeometry.cardCount {
            var card = deck.removeLast()
            card.isFaceUp = TriPeaksGeometry.row(of: index) == TriPeaksGeometry.rowCount - 1
            triPeaks.append(card)
        }
        var starter = deck.removeLast()
        starter.isFaceUp = true
        return GameState(
            variant: .tripeaks,
            stock: deck,
            waste: [starter],
            wasteDrawCount: 1,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            triPeaks: triPeaks
        )
    }

    /// Hand-constructed TriPeaks position for rules and planner tests. `slots`
    /// fills the peaks top-down (nil = played) and is padded with played slots;
    /// each present card's face is forced to the uncovered rule so the layout
    /// always passes validation. Cards not on the board, in the stock, or in the
    /// waste can be buried at the bottom of the waste so persistence-facing
    /// tests still see 52 cards without changing the match target.
    static func triPeaksState(
        slots: [Card?],
        stock: [Card] = [],
        waste: [Card],
        chainLength: Int = 0,
        fillWasteFromRemainder: Bool = false
    ) -> GameState {
        var triPeaks = slots
        if triPeaks.count < TriPeaksGeometry.cardCount {
            triPeaks.append(
                contentsOf: [Card?](repeating: nil, count: TriPeaksGeometry.cardCount - triPeaks.count)
            )
        }
        for index in triPeaks.indices {
            guard var card = triPeaks[index] else { continue }
            card.isFaceUp = TriPeaksGeometry.isUncovered(index, in: triPeaks)
            triPeaks[index] = card
        }
        var fullWaste = waste.map { card in
            var faceUp = card
            faceUp.isFaceUp = true
            return faceUp
        }
        if fillWasteFromRemainder {
            func identity(_ card: Card) -> Int {
                (Suit.allCases.firstIndex(of: card.suit) ?? 0) * 16 + card.rank.rawValue
            }
            let usedIdentities = Set((triPeaks.compactMap { $0 } + stock + fullWaste).map(identity))
            fullWaste = TestCards.fullDeck(faceUp: true).filter { card in
                !usedIdentities.contains(identity(card))
            } + fullWaste
        }
        return GameState(
            variant: .tripeaks,
            stock: stock,
            waste: fullWaste,
            wasteDrawCount: min(1, fullWaste.count),
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            triPeaks: triPeaks,
            triPeaksChainLength: chainLength
        )
    }

    /// A reproducible Golf deal matching the shape of `GameState.newGolfGame`.
    /// Mirrored by the hint probe's `seededGolfDeal` so seeds are comparable.
    static func seededGolfDeal(seed: UInt64) -> GameState {
        var deck = seededDeck(seed: seed, faceUp: false)
        var tableau: [[Card]] = []
        for _ in 0..<GolfGameRules.columnCount {
            var column: [Card] = []
            for _ in 0..<GolfGameRules.columnDepth {
                var card = deck.removeLast()
                card.isFaceUp = true
                column.append(card)
            }
            tableau.append(column)
        }
        var starter = deck.removeLast()
        starter.isFaceUp = true
        return GameState(
            variant: .golf,
            stock: deck,
            waste: [starter],
            wasteDrawCount: 1,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    /// Hand-constructed Golf position for rules and planner tests. `columns`
    /// is padded with empty columns to seven; every column card is forced face
    /// up so the layout always passes validation. Cards not on the board, in
    /// the stock, or in the waste can be buried at the bottom of the waste so
    /// persistence-facing tests still see 52 cards without changing the match
    /// target.
    static func golfState(
        columns: [[Card]],
        stock: [Card] = [],
        waste: [Card],
        fillWasteFromRemainder: Bool = false
    ) -> GameState {
        var tableau = columns.map { column in
            column.map { card in
                var faceUp = card
                faceUp.isFaceUp = true
                return faceUp
            }
        }
        if tableau.count < GolfGameRules.columnCount {
            tableau.append(
                contentsOf: [[Card]](repeating: [], count: GolfGameRules.columnCount - tableau.count)
            )
        }
        let faceDownStock = stock.map { card in
            var faceDown = card
            faceDown.isFaceUp = false
            return faceDown
        }
        var fullWaste = waste.map { card in
            var faceUp = card
            faceUp.isFaceUp = true
            return faceUp
        }
        if fillWasteFromRemainder {
            func identity(_ card: Card) -> Int {
                (Suit.allCases.firstIndex(of: card.suit) ?? 0) * 16 + card.rank.rawValue
            }
            let usedIdentities = Set((tableau.flatMap { $0 } + faceDownStock + fullWaste).map(identity))
            fullWaste = TestCards.fullDeck(faceUp: true).filter { card in
                !usedIdentities.contains(identity(card))
            } + fullWaste
        }
        return GameState(
            variant: .golf,
            stock: faceDownStock,
            waste: fullWaste,
            wasteDrawCount: min(1, fullWaste.count),
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    static func pyramidState(
        slots: [Card?],
        stock: [Card] = [],
        waste: [Card] = [],
        passesUsed: Int = 0,
        fillDiscardFromRemainder: Bool = false
    ) -> GameState {
        var pyramid = slots
        if pyramid.count < PyramidGeometry.cardCount {
            pyramid.append(
                contentsOf: [Card?](repeating: nil, count: PyramidGeometry.cardCount - pyramid.count)
            )
        }
        pyramid = pyramid.map { card in
            card.map { placed in
                var faceUp = placed
                faceUp.isFaceUp = true
                return faceUp
            }
        }
        var discard: [Card] = []
        if fillDiscardFromRemainder {
            func identity(_ card: Card) -> Int {
                (Suit.allCases.firstIndex(of: card.suit) ?? 0) * 16 + card.rank.rawValue
            }
            let usedIdentities = Set((pyramid.compactMap { $0 } + stock + waste).map(identity))
            discard = TestCards.fullDeck(faceUp: true).filter { card in
                !usedIdentities.contains(identity(card))
            }
        }
        return GameState(
            variant: .pyramid,
            stock: stock,
            waste: waste,
            wasteDrawCount: min(1, waste.count),
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            pyramid: pyramid,
            discard: discard,
            wasteRecyclesUsed: passesUsed
        )
    }

    private static func seededDeck(seed: UInt64, faceUp: Bool) -> [Card] {
        seededShuffle(TestCards.fullDeck(faceUp: faceUp), seed: seed)
    }

    private static func seededShuffle(_ cards: [Card], seed: UInt64) -> [Card] {
        var generator = SeededRandomNumberGenerator(seed: seed)
        var deck = cards
        for index in stride(from: deck.count - 1, through: 1, by: -1) {
            let swapIndex = Int(generator.next() % UInt64(index + 1))
            deck.swapAt(index, swapIndex)
        }
        return deck
    }
    static func emptyBoard() -> GameState {
        GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7)
        )
    }

    static func validPersistenceState(
        stockDrawCount: Int = DrawMode.three.rawValue,
        wasteDrawCount: Int = 0
    ) -> GameState {
        var deck = TestCards.fullDeck(faceUp: false)
        let stock = Array(deck.prefix(24))
        deck.removeFirst(24)

        var tableau: [[Card]] = Array(repeating: [], count: 7)
        var index = 0
        for pileIndex in 0..<7 {
            let count = pileIndex + 1
            var pile = Array(deck[index..<(index + count)])
            index += count
            for cardIndex in pile.indices {
                pile[cardIndex].isFaceUp = cardIndex == pile.count - 1
            }
            tableau[pileIndex] = pile
        }

        return GameState(
            stock: stock,
            waste: [],
            wasteDrawCount: min(max(0, wasteDrawCount), 0),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }

    static func almostWonForAutoFinish() -> GameState {
        var foundations = Array(repeating: [Card](), count: 4)
        for (foundationIndex, suit) in Suit.allCases.enumerated() {
            foundations[foundationIndex] = Rank.allCases
                .filter { $0 != .king }
                .map { rank in
                    TestCards.make(suit, rank, isFaceUp: true)
                }
        }

        return GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: foundations,
            tableau: [
                [TestCards.make(.spades, .king, isFaceUp: true)],
                [TestCards.make(.hearts, .king, isFaceUp: true)],
                [TestCards.make(.diamonds, .king, isFaceUp: true)],
                [TestCards.make(.clubs, .king, isFaceUp: true)],
                [],
                [],
                []
            ]
        )
    }
}

@MainActor
enum DateFixtures {
    static let reference = Date(timeIntervalSince1970: 1_700_000_000)

    static func plus(_ seconds: TimeInterval, from date: Date = reference) -> Date {
        date.addingTimeInterval(seconds)
    }
}

@MainActor
enum TestAssertions {
    static func assertSingleVisibleWasteCard(
        _ viewModel: SolitaireViewModel,
        expected: Card,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visible = viewModel.visibleWasteCards()
        XCTAssertEqual(visible.count, 1, file: file, line: line)
        XCTAssertEqual(visible.first?.id, expected.id, file: file, line: line)
    }
}

@MainActor
final class TestDateProvider: DateProviding {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
