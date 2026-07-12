import XCTest
@testable import Computer_Solitaire

@MainActor
final class SpiderPlannerTests: XCTestCase {
    func testHintIsDeterministicAcrossCalls() {
        let state = SpiderTestStates.board(
            tableau: [
                [TestCards.make(.spades, .six)],
                [TestCards.make(.hearts, .six)],
                [TestCards.make(.hearts, .five)],
                [TestCards.make(.clubs, .nine)]
            ]
        )

        let first = SpiderPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(SpiderPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal always has a pairing or reveal within easy reach, so a
        // small budget keeps the suite fast; production searches are capped by
        // the interactive deadline.
        let limits = SpiderPlanner.Limits(maxNodes: 2_000)
        for suitCount in SpiderSuitCount.allCases {
            for seed in 1...10 {
                let state = GameStateFixtures.seededSpiderDeal(seed: UInt64(seed), suitCount: suitCount)
                XCTAssertNotNil(
                    SpiderPlanner.bestHint(in: state, limits: limits),
                    "\(suitCount) seed \(seed): a fresh Spider deal should have a suggestible line"
                )
            }
        }
    }

    func testFollowingPlannedLinesNeverLoops() {
        // Hints follow one cached improving line to its end before re-planning,
        // and every completed line strictly improves the anchor position — that
        // ratchet is what makes looping impossible. Within a line, positions
        // never repeat; across lines a transient revisit is survivable, but the
        // same exact layout a third time would mean the hints loop.
        let limits = SpiderPlanner.Limits(maxNodes: 4_000)
        for seed in [11, 12] as [UInt64] {
            var state = GameStateFixtures.seededSpiderDeal(seed: seed, suitCount: .two)
            var visitCounts: [UInt64: Int] = [stateFingerprint(state): 1]
            var actions = 0
            while actions < 400 {
                guard case .line(let line) = SpiderPlanner.bestLine(in: state, limits: limits) else {
                    break
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

    func testHintPrefersRevealingLineOverPlainReshuffle() {
        // Moving the 9♣ onto a ten reveals a face-down card; moving the free
        // 10♦ onto the jack accomplishes nothing. The hint should pick the reveal.
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let nineClubs = TestCards.make(.clubs, .nine)
        let tenHearts = TestCards.make(.hearts, .ten)
        let tenDiamonds = TestCards.make(.diamonds, .ten)
        let jackSpades = TestCards.make(.spades, .jack)
        let state = SpiderTestStates.board(
            tableau: [[hiddenKing, nineClubs], [tenHearts], [tenDiamonds], [jackSpades]]
        )

        guard case .move(let move)? = SpiderPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineClubs.id)
    }

    func testHintPrefersSameSuitBuildWhenOtherwiseEqual() {
        // The 5♥ can land on either six; only the suited build can ever bank a
        // run, so the hint should target the 6♥.
        let fiveHearts = TestCards.make(.hearts, .five)
        let sixHearts = TestCards.make(.hearts, .six)
        let sixSpades = TestCards.make(.spades, .six)
        let state = SpiderTestStates.board(
            tableau: [[fiveHearts], [sixHearts], [sixSpades], [TestCards.make(.clubs, .two)]]
        )

        guard case .move(let move)? = SpiderPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, fiveHearts.id)
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testCompletingARunIsFoundAndModeled() {
        // One move banks a full spade run; the hint must be that move, and the
        // shared simulation must model the banking so cached-line replay,
        // tests, and the probe stay in lockstep with real play.
        let kingThroughTwoSpades = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.spades, $0) }
        let aceSpades = TestCards.make(.spades, .ace)
        let state = SpiderTestStates.board(
            tableau: [Array(kingThroughTwoSpades), [aceSpades], [TestCards.make(.hearts, .four)]]
        )

        guard case .move(let move)? = SpiderPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.map(\.id), [aceSpades.id])
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

    func testSuffixOfALongerRunIsMovedToCompleteARun() {
        // The 2♠A♠ suffix sits on an off-suit three; picking up just that
        // suffix onto the spade pile banks the run.
        let threeHearts = TestCards.make(.hearts, .three)
        let twoSpades = TestCards.make(.spades, .two)
        let aceSpades = TestCards.make(.spades, .ace)
        let kingThroughThreeSpades = Rank.allCases.reversed().dropLast(2)
            .map { TestCards.make(.spades, $0) }
        let state = SpiderTestStates.board(
            tableau: [
                [threeHearts, twoSpades, aceSpades],
                Array(kingThroughThreeSpades),
                [TestCards.make(.clubs, .nine)]
            ]
        )

        guard case .move(let move)? = SpiderPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.source, .tableau(pile: 0, index: 1))
        XCTAssertEqual(move.selection.cards.map(\.id), [twoSpades.id, aceSpades.id])
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testStockDealHintRespectsEmptyPileRule() {
        // With an empty pile the deal is illegal, so the line must start by
        // filling the space — never with a stock tap.
        let hiddenThree = TestCards.make(.diamonds, .three, isFaceUp: false)
        let nineHearts = TestCards.make(.hearts, .nine)
        var board = SpiderTestStates.fullBoard(topRank: .five)
        board.tableau[0] = []
        board.tableau[1] = [hiddenThree, nineHearts]
        board.stock = (1...10).map { _ in TestCards.make(.clubs, .two, isFaceUp: false) }

        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: board))
        guard case .move(let move)? = SpiderPlanner.bestHint(in: board) else {
            return XCTFail("Expected a move hint, never a stock tap over an empty pile")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineHearts.id)
        XCTAssertEqual(move.destination, .tableau(0))
        XCTAssertNotEqual(
            HintPlanner().bestHint(in: board, stockDrawCount: DrawMode.three.rawValue),
            .stockTap,
            "The hint stack must not point at the stock while a pile is empty"
        )
    }

    func testNoTableauProgressFallsBackToStockDealHint() {
        // Ten same-rank tops allow no tableau move at all; with stock in hand
        // the deal is the only way forward and the hint stack must say so.
        let stock = (1...10).map { _ in TestCards.make(.hearts, .two, isFaceUp: false) }
        let state = SpiderTestStates.fullBoard(topRank: .five, stock: stock)

        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
        XCTAssertEqual(
            HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.three.rawValue),
            .stockTap
        )
    }

    func testHintTargetsTheFirstEmptyColumn() {
        // With two empty columns the planner canonicalizes drops to the first;
        // the hint should never point at the second interchangeable column.
        let hiddenThree = TestCards.make(.diamonds, .three, isFaceUp: false)
        let nineSpades = TestCards.make(.spades, .nine)
        var board = SpiderTestStates.board(
            tableau: [
                [hiddenThree, nineSpades],
                [TestCards.make(.clubs, .five)],
                [TestCards.make(.clubs, .jack)]
            ]
        )
        board.tableau[3] = []
        board.tableau[4] = []

        guard case .move(let move)? = SpiderPlanner.bestHint(in: board) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineSpades.id)
        XCTAssertEqual(move.destination, .tableau(3))
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must
        // report truncation — not exhaustion, which would wrongly claim the
        // deal is dead — and the planner yields no unverified nudge.
        let limits = SpiderPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededSpiderDeal(seed: 5, suitCount: .two)

        guard case .noProgress(searchWasExhaustive: false) = SpiderPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(SpiderPlanner.bestHint(in: state, limits: limits))
    }

    func testDeadlockedStateReturnsNilAndReportsNoMoves() {
        // Ten same-rank tops, no empty pile, and no stock: nothing is legal.
        let state = SpiderTestStates.fullBoard(topRank: .five)

        XCTAssertNil(SpiderPlanner.bestHint(in: state))
        XCTAssertNil(HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.three.rawValue))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testHintPlannerWinsAKnownDealEndToEnd() {
        // Probe-verified winning seed: following the HintPlanner's cached lines
        // (including its stock-deal preparation fallback) plays this 1-suit
        // deal to a win without a single nil hint. Guards the whole hint stack.
        let planner = HintPlanner()
        var state = GameStateFixtures.seededSpiderDeal(seed: 1, suitCount: .one)
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
                next = SpiderGameRules.dealStockRow(in: &dealt) != nil ? dealt : nil
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

    private func applied(_ action: SpiderPlanner.PlannedAction, to state: GameState) -> GameState? {
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
            guard SpiderGameRules.dealStockRow(in: &next) != nil else { return nil }
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
