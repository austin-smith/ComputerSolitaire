import XCTest
@testable import Computer_Solitaire

@MainActor
final class ScorpionPlannerTests: XCTestCase {
    func testHintIsDeterministicAcrossCalls() {
        let state = ScorpionTestStates.board(
            tableau: [
                [TestCards.make(.spades, .six)],
                [TestCards.make(.spades, .seven)],
                [TestCards.make(.hearts, .five)],
                [TestCards.make(.clubs, .nine)]
            ]
        )

        let first = ScorpionPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(ScorpionPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal may hold no improving tableau line at all — the deal is
        // then the way forward, and the full hint stack must say so rather
        // than go silent. Runs the whole stack, stock fallback included.
        for seed in 1...10 {
            let state = GameStateFixtures.seededScorpionDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.three.rawValue),
                "seed \(seed): a fresh Scorpion deal should always yield a hint"
            )
        }
    }

    func testFollowingPlannedLinesNeverLoops() {
        // Hints follow one cached improving line to its end before re-planning,
        // and every completed line strictly improves the anchor position — that
        // ratchet is what makes looping impossible. Within a line, positions
        // never repeat; across lines a transient revisit is survivable, but the
        // same exact layout a third time would mean the hints loop.
        let limits = ScorpionPlanner.Limits(maxNodes: 4_000)
        for seed in [11, 12] as [UInt64] {
            var state = GameStateFixtures.seededScorpionDeal(seed: seed)
            var visitCounts: [UInt64: Int] = [stateFingerprint(state): 1]
            var actions = 0
            while actions < 400 {
                let line: [ScorpionPlanner.PlannedAction]
                switch ScorpionPlanner.bestLine(in: state, limits: limits) {
                case .line(let found):
                    line = found
                case .noProgress:
                    // Mirror the hint stack's fallback: deal if the stock
                    // remains, otherwise the game is over.
                    guard ScorpionGameRules.canDealFromStock(state: state) else {
                        return
                    }
                    line = [.stockDeal]
                }
                var lineKeys: Set<UInt64> = [stateFingerprint(state)]
                for action in line {
                    guard let next = applied(action, to: state) else {
                        return XCTFail("Planned action was not legal")
                    }
                    state = next
                    actions += 1
                    let key = stateFingerprint(state)
                    XCTAssertTrue(
                        lineKeys.insert(key).inserted,
                        "A planned line revisited a position"
                    )
                    let count = (visitCounts[key] ?? 0) + 1
                    visitCounts[key] = count
                    if count >= 3 {
                        return XCTFail("Following planned lines revisited the same position twice")
                    }
                }
            }
        }
    }

    func testHintPrefersRevealingLine() {
        // Moving the 7♣ onto the 8♣ reveals a face-down card; no other move
        // reveals anything. The hint should pick the reveal.
        let hiddenKing = TestCards.make(.hearts, .king, isFaceUp: false)
        let sevenClubs = TestCards.make(.clubs, .seven)
        let eightClubs = TestCards.make(.clubs, .eight)
        let state = ScorpionTestStates.board(
            tableau: [[hiddenKing, sevenClubs], [eightClubs], [TestCards.make(.diamonds, .four)]]
        )

        guard case .move(let move)? = ScorpionPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, sevenClubs.id)
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testKingToEmptyColumnEnablesReveal() {
        // The K♠ sits on a face-down card and lands nowhere but the empty
        // column; parking it there is the only reveal available.
        let hiddenQueen = TestCards.make(.diamonds, .queen, isFaceUp: false)
        let kingSpades = TestCards.make(.spades, .king)
        let state = ScorpionTestStates.board(
            tableau: [[hiddenQueen, kingSpades], [], [TestCards.make(.clubs, .four)]]
        )

        guard case .move(let move)? = ScorpionPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.map(\.id), [kingSpades.id])
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testCompletingARunIsFoundAndModeled() {
        // One move banks a full heart run; the hint must be that move, and the
        // shared simulation must model the banking so cached-line replay,
        // tests, and the probe stay in lockstep with real play.
        let kingThroughTwoHearts = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.hearts, $0) }
        let aceHearts = TestCards.make(.hearts, .ace)
        let state = ScorpionTestStates.board(
            tableau: [Array(kingThroughTwoHearts), [aceHearts], [TestCards.make(.spades, .four)]]
        )

        guard case .move(let move)? = ScorpionPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.map(\.id), [aceHearts.id])
        XCTAssertEqual(move.destination, .tableau(0))

        guard let next = AutoMoveAdvisor.simulatedState(
            afterMoving: move.selection,
            to: move.destination,
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        ) else {
            return XCTFail("Hinted move was not legal")
        }
        XCTAssertTrue(next.tableau[0].isEmpty, "Simulation must bank the completed run")
        XCTAssertEqual(next.foundations[0].count, 13)
        XCTAssertEqual(next.foundations[0].first?.rank, .ace)
    }

    func testNoTableauProgressFallsBackToStockDealHint() {
        // Seven stuck tops allow no tableau move at all; with stock in hand
        // the deal is the only way forward and the hint stack must say so.
        let stock = [
            TestCards.make(.hearts, .two, isFaceUp: false),
            TestCards.make(.clubs, .six, isFaceUp: false),
            TestCards.make(.diamonds, .ten, isFaceUp: false)
        ]
        let state = ScorpionTestStates.stuckBoard(stock: stock)

        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
        XCTAssertEqual(
            HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.three.rawValue),
            .stockTap
        )
    }

    func testDeadlockedStateReturnsNilAndReportsNoMoves() {
        // Seven stuck tops and no stock: nothing is legal, so the hint stack
        // stays silent — the loss is implicit, exactly like Spider's.
        let state = ScorpionTestStates.stuckBoard()

        XCTAssertNil(ScorpionPlanner.bestHint(in: state))
        XCTAssertNil(HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.three.rawValue))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testHintTargetsTheFirstInterchangeableEmptyColumn() {
        // With the stock spent, empty columns are interchangeable and the
        // planner canonicalizes drops to the first; the hint should never
        // point at a later twin.
        let hiddenThree = TestCards.make(.diamonds, .three, isFaceUp: false)
        let kingSpades = TestCards.make(.spades, .king)
        var board = ScorpionTestStates.board(
            tableau: [
                [hiddenThree, kingSpades],
                [TestCards.make(.clubs, .five)],
                [TestCards.make(.clubs, .jack)]
            ]
        )
        board.tableau[3] = []
        board.tableau[4] = []

        guard case .move(let move)? = ScorpionPlanner.bestHint(in: board) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, kingSpades.id)
        XCTAssertEqual(move.destination, .tableau(3))
    }

    func testPreDealEmptyFirstColumnsStayDistinct() {
        // While the stock is undealt, each of columns 0-2 awaits its own
        // dealt card, so an empty column there is NOT interchangeable with an
        // empty column among 3-6: a king may be sent to either class. The
        // planner must still generate the class-distinct drops.
        let kingSpades = TestCards.make(.spades, .king)
        let fourHearts = TestCards.make(.hearts, .four)
        var board = ScorpionTestStates.board(
            tableau: [
                [],
                [TestCards.make(.clubs, .five)],
                [TestCards.make(.clubs, .jack)],
                [fourHearts, kingSpades]
            ],
            stock: [
                TestCards.make(.hearts, .two, isFaceUp: false),
                TestCards.make(.clubs, .six, isFaceUp: false),
                TestCards.make(.diamonds, .ten, isFaceUp: false)
            ]
        )
        board.tableau[4] = []

        let selection = Selection(source: .tableau(pile: 3, index: 1), cards: [kingSpades])
        let destinations = AutoMoveAdvisor.legalDestinations(for: selection, in: board)
        XCTAssertTrue(destinations.contains(.tableau(0)))
        XCTAssertTrue(destinations.contains(.tableau(4)))
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must
        // report truncation — not exhaustion, which would wrongly claim the
        // tableau is dead — and the planner yields no unverified nudge.
        let limits = ScorpionPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededScorpionDeal(seed: 5)

        guard case .noProgress(searchWasExhaustive: false) = ScorpionPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(ScorpionPlanner.bestHint(in: state, limits: limits))
    }

    func testHintPlannerWinsAKnownDealEndToEnd() {
        // Probe-verified winning seed: following the HintPlanner's cached lines
        // (including its stock-deal fallback) plays this deal to a win without
        // a single nil hint. Guards the whole hint stack.
        let planner = HintPlanner()
        var state = GameStateFixtures.seededScorpionDeal(seed: 1)
        var actions = 0

        while actions < 500 {
            if state.isWon {
                return
            }
            guard let hint = planner.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue) else {
                return XCTFail("Hint stack gave up after \(actions) actions")
            }
            let next: GameState?
            switch hint {
            case .move(let move):
                next = AutoMoveAdvisor.simulatedState(
                    afterMoving: move.selection,
                    to: move.destination,
                    in: state,
                    stockDrawCount: DrawMode.three.rawValue
                )
            case .stockTap:
                var dealt = state
                next = ScorpionGameRules.dealStock(in: &dealt) != nil ? dealt : nil
            }
            guard let next else {
                return XCTFail("Hinted action was not legal after \(actions) actions")
            }
            state = next
            actions += 1
        }
        XCTFail("Did not win within 500 actions")
    }

    // MARK: - Helpers

    private func applied(_ action: ScorpionPlanner.PlannedAction, to state: GameState) -> GameState? {
        switch action {
        case .move(let selection, let destination):
            return AutoMoveAdvisor.simulatedState(
                afterMoving: selection,
                to: destination,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            )
        case .stockDeal:
            var next = state
            guard ScorpionGameRules.dealStock(in: &next) != nil else { return nil }
            return next
        }
    }

    private func stateFingerprint(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) { hash = (hash ^ UInt64(value)) &* 0x100000001b3 }
        func mix(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            mix(UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0)))
        }
        mix(UInt8(state.stock.count))
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
