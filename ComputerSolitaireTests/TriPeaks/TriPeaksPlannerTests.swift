import XCTest
@testable import Computer_Solitaire

@MainActor
final class TriPeaksPlannerTests: XCTestCase {
    // Probe-verified seeds (release-build sweep over seeded deals): the winning
    // seed's deal is cleared by following hints end-to-end; the unwinnable seed
    // is proved lost by the exhaustive search at the default budget.
    private static let winningSeed: UInt64 = 1
    private static let unwinnableSeed: UInt64 = 282

    func testHintIsDeterministicAcrossCalls() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .eight)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )

        let first = TriPeaksPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(TriPeaksPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal always has a suggestible line within easy reach, so a
        // small budget keeps the suite fast; production searches are capped by
        // the interactive deadline.
        let limits = TriPeaksPlanner.Limits(maxNodes: 20_000)
        for seed in 1...10 {
            let state = GameStateFixtures.seededTriPeaksDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                TriPeaksPlanner.bestHint(in: state, limits: limits),
                "Seed \(seed): a fresh TriPeaks deal should have a suggestible line"
            )
        }
    }

    func testWinningLineReplaysLegallyToAClearedBoard() {
        let state = GameStateFixtures.seededTriPeaksDeal(seed: Self.winningSeed)
        guard case .winningLine(let line) = TriPeaksPlanner.bestLine(in: state) else {
            return XCTFail("Probe-verified winning seed should produce a winning line")
        }

        var current = state
        for move in line {
            if case .play = move {
                replayThroughAdvisor(move, on: &current)
            } else {
                guard let next = TriPeaksPlanner.apply(move, to: current) else {
                    return XCTFail("Stock move in the winning line was not legal")
                }
                current = next
            }
        }
        XCTAssertTrue(current.isWon, "Replaying the winning line must clear the peaks")
    }

    func testKeyedMovesFollowTheSolutionLine() {
        let state = GameStateFixtures.seededTriPeaksDeal(seed: Self.winningSeed)
        guard case .winningLine(let line) = TriPeaksPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line")
        }

        let keyed = TriPeaksPlanner.keyedMoves(along: line, from: state)
        XCTAssertEqual(keyed.count, line.count, "Every position along the line gets its move")

        var current = state
        for move in line {
            XCTAssertEqual(keyed[TriPeaksPlanner.stateKey(for: current)], move)
            guard let next = TriPeaksPlanner.apply(move, to: current) else {
                return XCTFail("Line move was not legal")
            }
            current = next
        }
    }

    func testHintPlannerWinsAKnownDealEndToEnd() {
        // Probe-verified winning seed: following the HintPlanner's cached lines
        // (including stock taps) plays this deal to a win. Guards the whole
        // stack. The game is structurally bounded at 51 actions.
        let planner = HintPlanner()
        var state = GameStateFixtures.seededTriPeaksDeal(seed: Self.winningSeed)
        var steps = 0

        while steps < 60 {
            if state.isWon {
                return
            }
            guard let hint = planner.bestHint(in: state, stockDrawCount: 1) else {
                return XCTFail("Hint stack gave up after \(steps) steps")
            }
            guard let next = applied(hint, to: state) else {
                return XCTFail("Hinted action was not legal after \(steps) steps")
            }
            state = next
            steps += 1
        }
        XCTFail("Did not win within 60 steps")
    }

    func testUnwinnableDealIsProvedAndStillYieldsBestEffortHints() {
        var state = GameStateFixtures.seededTriPeaksDeal(seed: Self.unwinnableSeed)
        guard case .bestEffortLine(let line, let dealIsProvedUnwinnable) =
                TriPeaksPlanner.bestLine(in: state) else {
            return XCTFail("Probe-verified lost seed should produce a best-effort line")
        }
        XCTAssertTrue(dealIsProvedUnwinnable, "The exhausted search must prove this deal lost")
        XCTAssertFalse(line.isEmpty)

        // Following hints clears strictly more cards, never plays an illegal
        // move, and ends in silence rather than churn.
        let planner = HintPlanner()
        let clearedAtStart = state.triPeaks.count { $0 == nil }
        var steps = 0
        while steps < 60, let hint = planner.bestHint(in: state, stockDrawCount: 1) {
            guard let next = applied(hint, to: state) else {
                return XCTFail("Hinted action was not legal after \(steps) steps")
            }
            state = next
            steps += 1
        }
        XCTAssertLessThan(steps, 60, "Hints on a lost deal must eventually go silent")
        XCTAssertFalse(state.isWon)
        XCTAssertGreaterThan(
            state.triPeaks.count { $0 == nil },
            clearedAtStart,
            "Best-effort hints should still clear peak cards"
        )
    }

    func testFollowingHintsNeverRepeatsAPosition() {
        // Every TriPeaks move consumes a card, so followed lines can never
        // revisit a position; this guards the state mapping and cache.
        for seed in [Self.winningSeed, Self.unwinnableSeed] {
            let planner = HintPlanner()
            var state = GameStateFixtures.seededTriPeaksDeal(seed: seed)
            var seen: Set<String> = [TriPeaksPlanner.stateKey(for: state)]
            var steps = 0
            while steps < 60, !state.isWon,
                  let hint = planner.bestHint(in: state, stockDrawCount: 1) {
                guard let next = applied(hint, to: state) else {
                    return XCTFail("Seed \(seed): hinted action was not legal")
                }
                state = next
                steps += 1
                XCTAssertTrue(
                    seen.insert(TriPeaksPlanner.stateKey(for: state)).inserted,
                    "Seed \(seed): following hints revisited a position"
                )
            }
        }
    }

    func testDrawHintWhenNoPlayExists() {
        // The 9 cannot play on the 6, but drawing the 8 makes it playable: the
        // only winning line starts with a flip, so the hint is a stock tap.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .nine)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            stock: [TestCards.make(.clubs, .eight, isFaceUp: false)],
            waste: [TestCards.make(.diamonds, .six)]
        )

        guard case .winningLine(let line) = TriPeaksPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line through the flip")
        }
        XCTAssertEqual(line.first, .draw)
        XCTAssertEqual(TriPeaksPlanner.bestHint(in: state), .stockTap)
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testFlipTimingIsSearchedNotGreedy() {
        // The search dives plays-first, so wherever a winning line flips the
        // stock while plays were legal, every play-first alternative from that
        // position was explored and lost — the flip's timing is a verdict.
        // Verify the property holds at such a position on the winning seed.
        let deal = GameStateFixtures.seededTriPeaksDeal(seed: Self.winningSeed)
        guard case .winningLine(let line) = TriPeaksPlanner.bestLine(in: deal) else {
            return XCTFail("Expected a winning line")
        }

        var state = deal
        for move in line {
            let playsAvailable = AutoMoveAdvisor.candidateSelections(in: state).contains {
                !AutoMoveAdvisor.legalDestinations(for: $0, in: state).isEmpty
            }
            if move == .draw, playsAvailable {
                guard case .winningLine(let replanned) = TriPeaksPlanner.bestLine(in: state) else {
                    return XCTFail("Position on a winning line must stay winnable")
                }
                XCTAssertEqual(
                    replanned.first,
                    .draw,
                    "With plays available, a flip-first winning line means every play loses"
                )
                return
            }
            guard let next = TriPeaksPlanner.apply(move, to: state) else {
                return XCTFail("Line move was not legal")
            }
            state = next
        }
        // Seed 1's line does flip while plays are available, so the walk above
        // returns before reaching here. If a future deal or search change picks
        // a line that never does, this test would silently become a no-op —
        // fail loudly instead so the seed gets replaced.
        XCTFail("Winning line never flipped while plays were available — pick another seed")
    }

    func testWrapAdjacencyIsPlayable() {
        // Waste King: both the Queen and the Ace play (ranks wrap).
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .queen)
        slots[19] = TestCards.make(.hearts, .ace)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .king)]
        )

        for index in [18, 19] {
            let selection = Selection(
                source: .triPeaks(index: index),
                cards: [state.triPeaks[index]!]
            )
            XCTAssertEqual(
                AutoMoveAdvisor.legalDestinations(for: selection, in: state),
                [.waste],
                "Slot \(index) should play on the King"
            )
        }
        XCTAssertNotNil(TriPeaksPlanner.bestHint(in: state))
    }

    func testStateKeyMergesOnlyStrategicallyIdenticalStates() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        let base = GameStateFixtures.triPeaksState(
            slots: slots,
            stock: [TestCards.make(.clubs, .nine, isFaceUp: false)],
            waste: [TestCards.make(.diamonds, .seven)]
        )

        // Buried waste history and suits are strategically inert: same key.
        var differentHistory = base
        differentHistory.waste.insert(TestCards.make(.hearts, .two), at: 0)
        XCTAssertEqual(
            TriPeaksPlanner.stateKey(for: base),
            TriPeaksPlanner.stateKey(for: differentHistory)
        )
        var differentSuit = base
        differentSuit.waste[0] = TestCards.make(.clubs, .seven)
        XCTAssertEqual(
            TriPeaksPlanner.stateKey(for: base),
            TriPeaksPlanner.stateKey(for: differentSuit)
        )

        // The waste top rank, the board, and the stock all gate the future:
        // each changes the key.
        var differentTop = base
        differentTop.waste[0] = TestCards.make(.diamonds, .eight)
        XCTAssertNotEqual(
            TriPeaksPlanner.stateKey(for: base),
            TriPeaksPlanner.stateKey(for: differentTop)
        )
        var differentBoard = base
        differentBoard.triPeaks[18] = TestCards.make(.spades, .five, isFaceUp: true)
        XCTAssertNotEqual(
            TriPeaksPlanner.stateKey(for: base),
            TriPeaksPlanner.stateKey(for: differentBoard)
        )
        var differentStock = base
        differentStock.stock = [TestCards.make(.clubs, .ten, isFaceUp: false)]
        XCTAssertNotEqual(
            TriPeaksPlanner.stateKey(for: base),
            TriPeaksPlanner.stateKey(for: differentStock)
        )
    }

    func testMaterializeRejectsStaleMoves() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )
        let move = TriPeaksPlanner.Move.play(slot: 18)
        XCTAssertNotNil(TriPeaksPlanner.materialize(move, in: state))

        var clearedSlot = state
        clearedSlot.triPeaks[18] = nil
        XCTAssertNil(
            TriPeaksPlanner.materialize(move, in: clearedSlot),
            "A cached move for an emptied slot must not surface"
        )

        var changedTop = state
        changedTop.waste[0] = TestCards.make(.hearts, .ten)
        XCTAssertNil(
            TriPeaksPlanner.materialize(move, in: changedTop),
            "A cached move that is no longer adjacent must not surface"
        )

        XCTAssertNil(
            TriPeaksPlanner.materialize(.draw, in: state),
            "A draw hint with an empty stock must not surface"
        )
    }

    func testNoMovesWhenStockEmptyAndNoPlay() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .nine)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .six)]
        )

        guard case .noProgress(searchWasExhaustive: true) = TriPeaksPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive no-progress outcome")
        }
        XCTAssertNil(TriPeaksPlanner.bestHint(in: state))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testProvablyFutileDrawsGetNoHintButKeepButtonAlive() {
        // Draws are legal, but the lone 7 has no 6 or 8 anywhere: churning the
        // stock is provably futile, so the hint goes silent while the button
        // stays alive.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .seven)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            stock: [
                TestCards.make(.clubs, .two, isFaceUp: false),
                TestCards.make(.hearts, .jack, isFaceUp: false)
            ],
            waste: [TestCards.make(.diamonds, .four)]
        )

        guard case .noProgress(searchWasExhaustive: true) = TriPeaksPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive no-progress outcome")
        }
        XCTAssertNil(HintPlanner().bestHint(in: state, stockDrawCount: 1))
        // The position still has legal draws — the hint's nil is a verdict, not a bug.
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must
        // report truncation — not exhaustion, which would wrongly claim the
        // deal is dead.
        let limits = TriPeaksPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededTriPeaksDeal(seed: 5)

        guard case .noProgress(searchWasExhaustive: false) = TriPeaksPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(TriPeaksPlanner.bestHint(in: state, limits: limits))
    }

    func testHintsAreAlwaysLegalFromArbitraryMidGamePositions() {
        // Planner moves must materialize into advisor-legal moves from any
        // reachable position, not just fresh deals.
        for seed in 1...5 {
            var state = GameStateFixtures.seededTriPeaksDeal(seed: UInt64(seed))
            var generator = SeededRandomNumberGenerator(seed: UInt64(seed) &* 977)
            for _ in 0..<8 {
                var options: [(Selection, Destination)] = []
                for selection in AutoMoveAdvisor.candidateSelections(in: state) {
                    for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                        options.append((selection, destination))
                    }
                }
                if !state.stock.isEmpty, generator.next() % 2 == 0 {
                    state = TriPeaksPlanner.apply(.draw, to: state) ?? state
                } else if let choice = options.isEmpty
                    ? nil
                    : options[Int(generator.next() % UInt64(options.count))] {
                    state = AutoMoveAdvisor.simulatedState(
                        afterMoving: choice.0,
                        to: choice.1,
                        in: state,
                        stockDrawCount: 1
                    ) ?? state
                }
            }

            guard let hint = TriPeaksPlanner.bestHint(in: state) else { continue }
            switch hint {
            case .move(let move):
                XCTAssertTrue(
                    AutoMoveAdvisor.selectionMatchesState(move.selection, in: state),
                    "Seed \(seed): hinted selection did not match the state"
                )
                XCTAssertTrue(
                    AutoMoveAdvisor.legalDestinations(for: move.selection, in: state)
                        .contains(move.destination),
                    "Seed \(seed): hinted destination was not legal"
                )
            case .stockTap:
                XCTAssertFalse(
                    state.stock.isEmpty,
                    "Seed \(seed): stock tap hinted with a dead stock"
                )
            }
        }
    }

    // MARK: - Helpers

    private func applied(_ hint: HintAdvisor.Hint, to state: GameState) -> GameState? {
        switch hint {
        case .move(let move):
            return AutoMoveAdvisor.simulatedState(
                afterMoving: move.selection,
                to: move.destination,
                in: state,
                stockDrawCount: 1
            )
        case .stockTap:
            return TriPeaksPlanner.apply(.draw, to: state)
        }
    }

    private func replayThroughAdvisor(_ move: TriPeaksPlanner.Move, on state: inout GameState) {
        guard case .move(let hintMove)? = TriPeaksPlanner.materialize(move, in: state) else {
            return XCTFail("Play move failed to materialize")
        }
        guard let next = AutoMoveAdvisor.simulatedState(
            afterMoving: hintMove.selection,
            to: hintMove.destination,
            in: state,
            stockDrawCount: 1
        ) else {
            return XCTFail("Materialized move was not advisor-legal")
        }
        state = next
    }
}
