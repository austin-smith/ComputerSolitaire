import XCTest
@testable import Computer_Solitaire

@MainActor
final class KlondikePlannerTests: XCTestCase {
    func testHintIsDeterministicAcrossCalls() {
        let fiveHearts = TestCards.make(.hearts, .five)
        let sixClubs = TestCards.make(.clubs, .six)
        let sixSpades = TestCards.make(.spades, .six)
        let state = GameState(
            stock: [],
            waste: [fiveHearts],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: [[sixClubs], [sixSpades], [], [], [], [], []]
        )

        let first = KlondikePlanner.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(
                KlondikePlanner.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue),
                first
            )
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        for seed in 1...10 {
            let state = GameStateFixtures.seededKlondikeDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                KlondikePlanner.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue),
                "Seed \(seed): a fresh Klondike deal should have a suggestible line"
            )
        }
    }

    func testFollowingHintsNeverRevisitsAState() {
        // The planner must never recommend a cycle: following hints, the exact layout
        // should never repeat (stock taps cycle by design, so only moves are keyed).
        // Loop-freedom comes from deterministic search + shallow-line tie-breaking, not
        // budget size, so a small budget keeps this fast without weakening the property.
        let limits = KlondikePlanner.Limits(maxNodes: 400)
        for seed in [11, 12] as [UInt64] {
            var state = GameStateFixtures.seededKlondikeDeal(seed: seed)
            var seen = Set<UInt64>()
            for _ in 0..<120 {
                guard let hint = KlondikePlanner.bestHint(
                    in: state,
                    stockDrawCount: DrawMode.three.rawValue,
                    limits: limits
                ) else {
                    break
                }
                switch hint {
                case .move(let move):
                    guard let next = AutoMoveAdvisor.simulatedState(
                        afterMoving: move.selection,
                        to: move.destination,
                        in: state,
                        stockDrawCount: DrawMode.three.rawValue
                    ) else {
                        return XCTFail("Hinted move was not legal")
                    }
                    state = next
                    XCTAssertTrue(
                        seen.insert(stateFingerprint(state)).inserted,
                        "Hint sequence revisited an earlier position"
                    )
                case .stockTap:
                    guard let next = stockTap(state, drawCount: DrawMode.three.rawValue) else {
                        return XCTFail("Stock tap hinted with nothing to tap")
                    }
                    state = next
                }
            }
        }
    }

    func testHintPrefersRevealingLineOverPlainReshuffle() {
        // Moving the 9♣ onto the red 10 reveals a face-down card; moving the free 10♦
        // onto the black jack accomplishes nothing. The hint should pick the reveal.
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let nineClubs = TestCards.make(.clubs, .nine)
        let tenHearts = TestCards.make(.hearts, .ten)
        let tenDiamonds = TestCards.make(.diamonds, .ten)
        let jackSpades = TestCards.make(.spades, .jack)
        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenKing, nineClubs], [tenHearts], [tenDiamonds], [jackSpades], [], [], []]
        )

        guard case .move(let move)? = KlondikePlanner.bestHint(
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        ) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineClubs.id)
        XCTAssertEqual(move.destination, .tableau(1))
    }

    // MARK: - Helpers

    private func stockTap(_ state: GameState, drawCount: Int) -> GameState? {
        var next = state
        if !next.stock.isEmpty {
            let cardsToDraw = min(drawCount, next.stock.count)
            for _ in 0..<cardsToDraw {
                var card = next.stock.removeLast()
                card.isFaceUp = true
                next.waste.append(card)
            }
            next.wasteDrawCount = cardsToDraw
            return next
        }
        guard !next.waste.isEmpty else { return nil }
        next.stock = next.waste.reversed().map { card in
            var recycled = card
            recycled.isFaceUp = false
            return recycled
        }
        next.waste.removeAll()
        next.wasteDrawCount = 0
        return next
    }

    private func stateFingerprint(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) { hash = (hash ^ UInt64(value)) &* 0x100000001b3 }
        func mix(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            mix(UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0)))
        }
        for card in state.stock { mix(card: card) }
        mix(0xFF)
        for card in state.waste { mix(card: card) }
        mix(UInt8(min(255, max(0, state.wasteDrawCount))))
        for pile in state.foundations {
            mix(0xFE)
            for card in pile { mix(card: card) }
        }
        for pile in state.tableau {
            mix(0xFD)
            for card in pile { mix(card: card) }
        }
        return hash
    }
}
