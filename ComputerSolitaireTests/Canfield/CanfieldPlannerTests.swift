import XCTest
@testable import Computer_Solitaire

@MainActor
final class CanfieldPlannerTests: XCTestCase {
    // MARK: - Action application

    func testStockTapTurnsThreeCardsPreservingOrder() throws {
        let state = GameStateFixtures.seededCanfieldDeal(seed: 11)
        let expected = Array(state.stock.suffix(3)).reversed().map(\.id)

        let next = try XCTUnwrap(CanfieldPlanner.apply(.stockTap, to: state))

        XCTAssertEqual(next.waste.map(\.id), expected)
        XCTAssertTrue(next.waste.allSatisfy(\.isFaceUp))
        XCTAssertEqual(next.wasteDrawCount, 3)
        XCTAssertEqual(next.stock.count, state.stock.count - 3)
    }

    func testStockTapOnASpentStockRecyclesTheWaste() throws {
        var state = GameStateFixtures.seededCanfieldDeal(seed: 11)
        state.waste = state.stock.reversed().map { card in
            var faceUp = card
            faceUp.isFaceUp = true
            return faceUp
        }
        state.stock = []
        state.wasteDrawCount = 3
        let wasteOrder = state.waste.map(\.id)

        let next = try XCTUnwrap(CanfieldPlanner.apply(.stockTap, to: state))

        XCTAssertTrue(next.waste.isEmpty)
        XCTAssertEqual(next.stock.map(\.id), wasteOrder.reversed())
        XCTAssertTrue(next.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertEqual(next.wasteDrawCount, 0)

        XCTAssertNil(
            CanfieldPlanner.apply(.stockTap, to: GameStateFixtures.canfieldState(columns: [])),
            "A tap with no stock and no waste is meaningless"
        )
    }

    func testApplyingATableauMoveMirrorsTheReserveFill() throws {
        let reserveTop = TestCards.make(.diamonds, .queen)
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.clubs, .six)],
                [TestCards.make(.hearts, .seven)]
            ],
            reserve: [TestCards.make(.spades, .two), reserveTop],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: state.tableau[0])

        let next = try XCTUnwrap(
            CanfieldPlanner.apply(.move(selection: selection, destination: .tableau(1)), to: state)
        )

        XCTAssertEqual(next.tableau[0].first?.id, reserveTop.id)
        XCTAssertEqual(next.reserve.count, 1)
        XCTAssertEqual(next.reserve.last?.isFaceUp, true)
        XCTAssertEqual(next.tableau[1].count, 2)
    }

    func testApplyingAWastePlayKeepsTheUncoveredTopAvailable() throws {
        // The planner mirrors the session: playing the last fanned card
        // uncovers the card beneath, which stays in the one-card fan rather
        // than being buried until the next tap.
        let buried = TestCards.make(.clubs, .nine)
        let fanned = TestCards.make(.hearts, .five)
        let state = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.spades, .six)]],
            waste: [buried, fanned],
            foundations: [[TestCards.make(.diamonds, .ten)]],
            wasteDrawCount: 1
        )
        let selection = Selection(source: .waste, cards: [fanned])

        let next = try XCTUnwrap(
            CanfieldPlanner.apply(.move(selection: selection, destination: .tableau(0)), to: state)
        )

        XCTAssertEqual(next.wasteDrawCount, 1)
        XCTAssertEqual(next.waste.last?.id, buried.id)
        XCTAssertFalse(
            AutoMoveAdvisor.candidateSelections(in: next)
                .filter { $0.source == .waste }
                .isEmpty,
            "The uncovered waste top must stay a planner candidate"
        )
    }

    // MARK: - Search

    func testBestLineBanksAnAvailableBaseCard() throws {
        // The base-rank 5♥ sits on a tableau pile; banking it is pure
        // permanent progress, so the best line must start moving toward it.
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.hearts, .five)],
                [TestCards.make(.spades, .nine)],
                [TestCards.make(.diamonds, .jack)],
                [TestCards.make(.clubs, .three)]
            ],
            reserve: [TestCards.make(.clubs, .ten)],
            foundations: [[TestCards.make(.spades, .five)]],
            fillStockFromRemainder: true
        )

        guard case .line(let actions) = CanfieldPlanner.bestLine(in: state) else {
            return XCTFail("A base card in the open must yield an improving line")
        }
        var current = state
        for action in actions {
            current = try XCTUnwrap(CanfieldPlanner.apply(action, to: current))
        }
        XCTAssertGreaterThan(
            current.foundations.reduce(0) { $0 + $1.count },
            state.foundations.reduce(0) { $0 + $1.count },
            "The improving line banks at least one card"
        )
    }

    func testBestLineFinishesAWonEndgame() throws {
        // Base five, every foundation one card short; the four closing fours
        // wait as tableau tops. The line must run to the win.
        var foundations: [[Card]] = []
        for suit in Suit.allCases {
            var pile: [Card] = []
            for offset in 0..<(Rank.allCases.count - 1) {
                let rawValue = (Rank.five.rawValue - 1 + offset) % Rank.allCases.count + 1
                pile.append(TestCards.make(suit, Rank(rawValue: rawValue) ?? .ace))
            }
            foundations.append(pile)
        }
        let columns = Suit.allCases.map { suit in
            [TestCards.make(suit, .four)]
        }
        let state = GameStateFixtures.canfieldState(columns: columns, foundations: foundations)

        guard case .line(let actions) = CanfieldPlanner.bestLine(in: state) else {
            return XCTFail("A four-move win must be found")
        }
        var current = state
        for action in actions {
            current = try XCTUnwrap(CanfieldPlanner.apply(action, to: current))
        }
        XCTAssertTrue(current.isWon)
    }

    func testExhaustedDeadPositionIsAProofAndSilencesTheHint() {
        // No stock, no waste, no reserve, and four same-rank piles that can
        // neither pack nor bank: the whole reachable space is this position.
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.spades, .eight)],
                [TestCards.make(.clubs, .eight)],
                [TestCards.make(.hearts, .eight)],
                [TestCards.make(.diamonds, .eight)]
            ],
            foundations: [[TestCards.make(.spades, .five)]]
        )

        guard case .noProgress(let searchWasExhaustive) = CanfieldPlanner.bestLine(in: state) else {
            return XCTFail("A dead position must not produce a line")
        }
        XCTAssertTrue(searchWasExhaustive, "The tiny reachable space must be fully searched")
        XCTAssertNil(
            HintAdvisor.bestHint(in: state, stockDrawCount: CanfieldGameRules.stockDrawCount),
            "An exhausted search is a proof; a tap hint would churn a dead game"
        )
    }

    // MARK: - Cached lines

    func testKeyedActionsFollowTheLinePositionByPosition() throws {
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.hearts, .five)],
                [TestCards.make(.spades, .nine)],
                [TestCards.make(.diamonds, .jack)],
                [TestCards.make(.clubs, .three)]
            ],
            reserve: [TestCards.make(.clubs, .ten)],
            foundations: [[TestCards.make(.spades, .five)]],
            fillStockFromRemainder: true
        )
        guard case .line(let actions) = CanfieldPlanner.bestLine(in: state) else {
            return XCTFail("Expected an improving line")
        }

        let keyed = CanfieldPlanner.keyedActions(along: actions, from: state)
        var current = state
        for expected in actions {
            let key = CanfieldPlanner.stateKey(for: current)
            let cached = try XCTUnwrap(keyed[key], "Every position along the line is keyed")
            XCTAssertNotNil(
                CanfieldPlanner.materialize(cached, in: current),
                "The cached action must re-validate against its position"
            )
            current = try XCTUnwrap(CanfieldPlanner.apply(expected, to: current))
        }
    }

    func testStateKeyDistinguishesStockOrderAfterARecycle() {
        // Two positions with identical counts but different stock orders must
        // not share a key — recycling rebuilds the stock from the waste, so a
        // count is not an identity.
        let cardA = TestCards.make(.spades, .two, isFaceUp: false)
        let cardB = TestCards.make(.hearts, .nine, isFaceUp: false)
        var state = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.clubs, .six)]],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        state.stock = [cardA, cardB]
        var swapped = state
        swapped.stock = [cardB, cardA]

        XCTAssertNotEqual(
            CanfieldPlanner.stateKey(for: state),
            CanfieldPlanner.stateKey(for: swapped)
        )
    }
}
