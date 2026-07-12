import XCTest
@testable import Computer_Solitaire

@MainActor
final class YukonPlannerTests: XCTestCase {
    func testHintIsDeterministicAcrossCalls() {
        let sixClubs = TestCards.make(.clubs, .six)
        let sixSpades = TestCards.make(.spades, .six)
        let fiveHearts = TestCards.make(.hearts, .five)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[sixClubs], [sixSpades], [fiveHearts], [], [], [], []]
        )

        let first = YukonPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(YukonPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal always has a reveal within easy reach, so a small budget keeps
        // the suite fast; production searches are capped by the interactive deadline.
        let limits = YukonPlanner.Limits(maxNodes: 2_000)
        for seed in 1...10 {
            let state = GameStateFixtures.seededYukonDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                YukonPlanner.bestHint(in: state, limits: limits),
                "Seed \(seed): a fresh Yukon deal should have a suggestible line"
            )
        }
    }

    func testFollowingPlannedLinesNeverLoops() {
        // Hints follow one cached improving line to its end before re-planning, and
        // every completed line strictly improves the anchor position — that ratchet is
        // what makes looping impossible. Within a line, positions never repeat (the
        // search graph is acyclic); across lines a transient revisit is survivable,
        // but seeing the same exact layout a third time would mean the hints loop.
        let limits = YukonPlanner.Limits(maxNodes: 4_000)
        for seed in [11, 12] as [UInt64] {
            var state = GameStateFixtures.seededYukonDeal(seed: seed)
            var visitCounts: [UInt64: Int] = [stateFingerprint(state): 1]
            var moves = 0
            while moves < 300 {
                guard case .line(let line) = YukonPlanner.bestLine(in: state, limits: limits) else {
                    break
                }
                var lineKeys: Set<UInt64> = [stateFingerprint(state)]
                for move in line {
                    guard let next = AutoMoveAdvisor.simulatedState(
                        afterMoving: move.selection,
                        to: move.destination,
                        in: state,
                        stockDrawCount: DrawMode.three.rawValue
                    ) else {
                        return XCTFail("Planned move was not legal")
                    }
                    state = next
                    moves += 1
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
        // Moving the 9♣ onto the red 10 reveals a face-down card; moving the free 10♦
        // onto the black jack accomplishes nothing. The hint should pick the reveal.
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let nineClubs = TestCards.make(.clubs, .nine)
        let tenHearts = TestCards.make(.hearts, .ten)
        let tenDiamonds = TestCards.make(.diamonds, .ten)
        let jackSpades = TestCards.make(.spades, .jack)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenKing, nineClubs], [tenHearts], [tenDiamonds], [jackSpades], [], [], []]
        )

        guard case .move(let move)? = YukonPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineClubs.id)
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testHintGrabsUnorderedGroupWhenThatIsTheOnlyRevealingLine() {
        // The 7♥ is buried under an out-of-sequence 2♠; the only progress is grabbing
        // both together onto the 8♠, which a sequence-only picker could never suggest.
        let hiddenFour = TestCards.make(.diamonds, .four, isFaceUp: false)
        let sevenHearts = TestCards.make(.hearts, .seven)
        let twoSpades = TestCards.make(.spades, .two)
        let eightSpades = TestCards.make(.spades, .eight)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenFour, sevenHearts, twoSpades], [eightSpades], [], [], [], [], []]
        )

        guard case .move(let move)? = YukonPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.source, .tableau(pile: 0, index: 1))
        XCTAssertEqual(move.selection.cards.map(\.id), [sevenHearts.id, twoSpades.id])
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testHintTargetsTheFirstEmptyColumn() {
        // With two empty columns the planner canonicalizes king drops to the first one;
        // the hint should never point at the second interchangeable column.
        let hiddenThree = TestCards.make(.diamonds, .three, isFaceUp: false)
        let kingSpades = TestCards.make(.spades, .king)
        let nineHearts = TestCards.make(.hearts, .nine)
        let sevenClubs = TestCards.make(.clubs, .seven)
        let nineSpades = TestCards.make(.spades, .nine)
        let jackClubs = TestCards.make(.clubs, .jack)
        let fiveSpades = TestCards.make(.spades, .five)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [
                [hiddenThree, kingSpades, nineHearts],
                [sevenClubs],
                [nineSpades],
                [jackClubs],
                [],
                [],
                [fiveSpades]
            ]
        )

        guard case .move(let move)? = YukonPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.source, .tableau(pile: 0, index: 1))
        XCTAssertEqual(move.destination, .tableau(4))
    }

    func testRedundantKingShuffleYieldsNoHintAndNoAvailableMove() {
        // A full king-led pile next to empty columns is a strategic dead end: moving it
        // sideways is a no-op, so both the planner and the move-exists check say stop.
        let kingSpades = TestCards.make(.spades, .king)
        let nineHearts = TestCards.make(.hearts, .nine)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[kingSpades, nineHearts], [], [], [], [], [], []]
        )

        XCTAssertNil(YukonPlanner.bestHint(in: state))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testRollbackOnlyRescueIsFoundInsteadOfDeclaredStuck() {
        // The 4♠ hides the only face-down card, and both of its landing spots (the
        // red fives) are gone — one banked on the foundation. The only rescue is
        // rolling the 5♥ back onto the 6♣, landing the 4♠ on it, and flipping the
        // hidden card. If rollbacks were missing from the search, this position
        // would be misreported as provably stuck while productive play exists.
        let heartsFoundation = [Rank.ace, .two, .three, .four, .five]
            .map { TestCards.make(.hearts, $0) }
        let hiddenNine = TestCards.make(.diamonds, .nine, isFaceUp: false)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [heartsFoundation, [], [], []],
            tableau: [
                [hiddenNine, TestCards.make(.spades, .four)],
                [TestCards.make(.clubs, .six)],
                [TestCards.make(.diamonds, .king), TestCards.make(.spades, .queen)],
                [TestCards.make(.hearts, .king)],
                [TestCards.make(.clubs, .three)],
                [TestCards.make(.spades, .nine)],
                [TestCards.make(.clubs, .jack)]
            ]
        )

        // The Q♠ shuttle keeps ordinary moves available, so the position is live.
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))

        guard case .line(let line) = YukonPlanner.bestLine(in: state) else {
            return XCTFail("Expected the search to find the rollback rescue line")
        }
        guard let firstMove = line.first else {
            return XCTFail("Expected a non-empty line")
        }
        XCTAssertEqual(firstMove.selection.source, .foundation(pile: 0))
        XCTAssertEqual(firstMove.destination, .tableau(1))

        guard case .move(let hint)? = HintPlanner().bestHint(
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        ) else {
            return XCTFail("Expected the hint stack to surface the rollback")
        }
        XCTAssertEqual(hint.selection.source, .foundation(pile: 0))
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must report
        // truncation — not exhaustion, which would wrongly claim the deal is dead —
        // and the hint contract yields silence rather than an unverified nudge.
        let limits = YukonPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededYukonDeal(seed: 5)

        guard case .noProgress(searchWasExhaustive: false) = YukonPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(YukonPlanner.bestHint(in: state, limits: limits))
    }

    func testRollbackOnlyPositionKeepsHintButtonAliveAndHintsTheRollback() {
        // Same rescue as above, but the rollback is the ONLY legal move on the
        // board: every face-up tableau card is black, so no tableau move exists.
        // The availability check must still report a move for Yukon — its planner
        // can turn the rollback into a hint — or the button dies on a live game.
        let heartsFoundation = [Rank.ace, .two, .three, .four, .five]
            .map { TestCards.make(.hearts, $0) }
        let hiddenNine = TestCards.make(.diamonds, .nine, isFaceUp: false)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [heartsFoundation, [], [], []],
            tableau: [
                [hiddenNine, TestCards.make(.spades, .four)],
                [TestCards.make(.clubs, .six)],
                [TestCards.make(.spades, .queen)],
                [TestCards.make(.clubs, .king)],
                [TestCards.make(.clubs, .three)],
                [TestCards.make(.spades, .nine)],
                [TestCards.make(.clubs, .jack)]
            ]
        )

        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))

        guard case .move(let hint)? = HintPlanner().bestHint(
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        ) else {
            return XCTFail("Expected the hint stack to surface the rollback rescue")
        }
        XCTAssertEqual(hint.selection.source, .foundation(pile: 0))
        XCTAssertEqual(hint.destination, .tableau(1))
    }

    func testProvablyStuckPositionWithLegalMovesGetsNoHint() {
        // The 5♠ can shuttle between the two red sixes forever, but no reveal or
        // foundation progress is reachable anywhere. The search exhausts the reachable
        // positions, and the hint stack must report "no useful move" instead of
        // suggesting the shuttle — a deterministic fallback would ping-pong it.
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [
                [TestCards.make(.hearts, .six), TestCards.make(.spades, .five)],
                [TestCards.make(.diamonds, .six)],
                [TestCards.make(.clubs, .three)],
                [TestCards.make(.clubs, .eight)],
                [TestCards.make(.clubs, .nine)],
                [TestCards.make(.spades, .jack)],
                [TestCards.make(.clubs, .king)]
            ]
        )

        guard case .noProgress(searchWasExhaustive: true) = YukonPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive no-progress search outcome")
        }
        XCTAssertNil(HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.three.rawValue))
        // The position still has legal moves — the hint's nil is a verdict, not a bug.
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testDeadlockedStateReturnsNil() {
        // Every face-up card is black, so no tableau landing exists; no tops are aces
        // and no column is empty, so nothing else is legal either.
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [
                [TestCards.make(.spades, .two, isFaceUp: false), TestCards.make(.spades, .five)],
                [TestCards.make(.clubs, .three)],
                [TestCards.make(.spades, .seven)],
                [TestCards.make(.clubs, .nine)],
                [TestCards.make(.spades, .jack)],
                [TestCards.make(.clubs, .king)],
                [TestCards.make(.clubs, .six)]
            ]
        )

        XCTAssertNil(YukonPlanner.bestHint(in: state))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testHintPlannerWinsAKnownDealEndToEnd() {
        // Probe-verified winning seed: following the HintPlanner's cached lines plays
        // this deal to a win without a single nil hint. Guards the whole hint stack.
        let planner = HintPlanner()
        var state = GameStateFixtures.seededYukonDeal(seed: 7)
        var moves = 0

        while moves < 400 {
            if state.isWon {
                return
            }
            guard let hint = planner.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue) else {
                return XCTFail("Hint stack gave up after \(moves) moves")
            }
            guard case .move(let move) = hint else {
                return XCTFail("Yukon hinted a stock tap")
            }
            guard let next = AutoMoveAdvisor.simulatedState(
                afterMoving: move.selection,
                to: move.destination,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            ) else {
                return XCTFail("Hinted move was not legal after \(moves) moves")
            }
            state = next
            moves += 1
        }
        XCTFail("Did not win within 400 moves")
    }

    // MARK: - Helpers

    private func stateFingerprint(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) { hash = (hash ^ UInt64(value)) &* 0x100000001b3 }
        func mix(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            mix(UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0)))
        }
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
