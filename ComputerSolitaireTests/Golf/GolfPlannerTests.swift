import XCTest
@testable import Computer_Solitaire

@MainActor
final class GolfPlannerTests: XCTestCase {
    /// The first seeded deal a *small* exhaustive search proves winnable.
    /// Scanning a fixed seed range is deterministic and cheap — no magic
    /// probe-verified constant to go stale. The node cap matters: the
    /// end-to-end tests follow the real `HintPlanner`, whose interactive
    /// deadline may truncate a search that needs the planner's full budget
    /// (designed behavior), so the staged deal must be one whose winning
    /// line is found well inside any deadline, debug builds included.
    private func firstWinnableDeal(in seeds: ClosedRange<UInt64> = 1...50) -> GameState? {
        let limits = GolfPlanner.Limits(maxNodes: 100_000)
        for seed in seeds {
            let state = GameStateFixtures.seededGolfDeal(seed: seed)
            if case .winningLine = GolfPlanner.bestLine(in: state, limits: limits) {
                return state
            }
        }
        return nil
    }

    private func firstProvedUnwinnableDeal(in seeds: ClosedRange<UInt64> = 1...50) -> GameState? {
        for seed in seeds {
            let state = GameStateFixtures.seededGolfDeal(seed: seed)
            if case .bestEffortLine(_, dealIsProvedUnwinnable: true) = GolfPlanner.bestLine(in: state) {
                return state
            }
        }
        return nil
    }

    func testHintIsDeterministicAcrossCalls() {
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.spades, .six)],
                [TestCards.make(.hearts, .eight)]
            ],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )

        let first = GolfPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(GolfPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal always has a suggestible line within easy reach, so a
        // small budget keeps the suite fast; production searches are capped by
        // the interactive deadline.
        let limits = GolfPlanner.Limits(maxNodes: 20_000)
        for seed in 1...10 {
            let state = GameStateFixtures.seededGolfDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                GolfPlanner.bestHint(in: state, limits: limits),
                "Seed \(seed): a fresh Golf deal should have a suggestible line"
            )
        }
    }

    func testWinningLineReplaysLegallyToAClearedBoard() throws {
        let state = try XCTUnwrap(
            firstWinnableDeal(),
            "No winnable deal in the scanned seed range — widen the range"
        )
        guard case .winningLine(let line) = GolfPlanner.bestLine(in: state) else {
            return XCTFail("The scanned winnable deal must reproduce its winning line")
        }

        var current = state
        for move in line {
            if case .play = move {
                replayThroughAdvisor(move, on: &current)
            } else {
                guard let next = GolfPlanner.apply(move, to: current) else {
                    return XCTFail("Stock move in the winning line was not legal")
                }
                current = next
            }
        }
        XCTAssertTrue(current.isWon, "Replaying the winning line must clear the columns")
    }

    func testKeyedMovesFollowTheSolutionLine() throws {
        let state = try XCTUnwrap(firstWinnableDeal())
        guard case .winningLine(let line) = GolfPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line")
        }

        let keyed = GolfPlanner.keyedMoves(along: line, from: state)
        XCTAssertEqual(keyed.count, line.count, "Every position along the line gets its move")

        var current = state
        for move in line {
            XCTAssertEqual(keyed[GolfPlanner.stateKey(for: current)], move)
            guard let next = GolfPlanner.apply(move, to: current) else {
                return XCTFail("Line move was not legal")
            }
            current = next
        }
    }

    func testHintPlannerWinsAKnownDealEndToEnd() throws {
        // Following the HintPlanner's cached lines (including stock taps)
        // plays a winnable deal to a win. Guards the whole stack. The game is
        // structurally bounded at 51 actions.
        var state = try XCTUnwrap(firstWinnableDeal())
        let planner = HintPlanner()
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

    func testUnwinnableDealIsProvedAndStillYieldsBestEffortHints() throws {
        var state = try XCTUnwrap(
            firstProvedUnwinnableDeal(),
            "No proved-unwinnable deal in the scanned seed range — widen the range"
        )
        guard case .bestEffortLine(let line, dealIsProvedUnwinnable: true) =
                GolfPlanner.bestLine(in: state) else {
            return XCTFail("The scanned lost deal must reproduce its best-effort line")
        }
        XCTAssertFalse(line.isEmpty)

        // Following hints clears strictly more cards, never plays an illegal
        // move, and ends in silence rather than churn.
        let planner = HintPlanner()
        func boardCount(_ state: GameState) -> Int {
            state.tableau.reduce(0) { $0 + $1.count }
        }
        let boardAtStart = boardCount(state)
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
        XCTAssertLessThan(
            boardCount(state),
            boardAtStart,
            "Best-effort hints should still clear column cards"
        )
    }

    func testFollowingHintsNeverRepeatsAPosition() {
        // Every Golf move consumes a card, so followed lines can never
        // revisit a position; this guards the state mapping and cache.
        for seed in 1...5 {
            let planner = HintPlanner()
            var state = GameStateFixtures.seededGolfDeal(seed: UInt64(seed))
            var seen: Set<String> = [GolfPlanner.stateKey(for: state)]
            var steps = 0
            while steps < 60, !state.isWon,
                  let hint = planner.bestHint(in: state, stockDrawCount: 1) {
                guard let next = applied(hint, to: state) else {
                    return XCTFail("Seed \(seed): hinted action was not legal")
                }
                state = next
                steps += 1
                XCTAssertTrue(
                    seen.insert(GolfPlanner.stateKey(for: state)).inserted,
                    "Seed \(seed): following hints revisited a position"
                )
            }
        }
    }

    func testDrawHintWhenNoPlayExists() {
        // The 9 cannot play on the 6, but drawing the 8 makes it playable: the
        // only winning line starts with a flip, so the hint is a stock tap.
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .nine)]],
            stock: [TestCards.make(.clubs, .eight)],
            waste: [TestCards.make(.diamonds, .six)],
            fillWasteFromRemainder: true
        )

        guard case .winningLine(let line) = GolfPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line through the flip")
        }
        XCTAssertEqual(line.first, .draw)
        XCTAssertEqual(GolfPlanner.bestHint(in: state), .stockTap)
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testWasteTopKingForcesADraw() {
        // Strict Golf: nothing plays on a King — not even the exposed Queen.
        // Flipping the Jack revives the board (the Queen plays on it), so the
        // only winning line is draw, then play the Queen.
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .queen)]],
            stock: [TestCards.make(.clubs, .jack)],
            waste: [TestCards.make(.diamonds, .king)],
            fillWasteFromRemainder: true
        )

        guard case .winningLine(let line) = GolfPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line through the flip")
        }
        XCTAssertEqual(
            line.first,
            .draw,
            "A waste-top King is dead: the first move must be the flip"
        )
        XCTAssertEqual(GolfPlanner.bestHint(in: state), .stockTap)
    }

    func testNoWrapMakesKingOnlyBoardsUnwinnable() {
        // Waste Ace, lone King on the board: only a wraparound link could
        // clear it, and strict Golf has none. With stock remaining the search
        // must prove the deal lost rather than churn.
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .king)]],
            stock: [
                TestCards.make(.clubs, .ace),
                TestCards.make(.hearts, .seven)
            ],
            waste: [TestCards.make(.diamonds, .ace)],
            fillWasteFromRemainder: true
        )

        guard case .noProgress(searchWasExhaustive: true) = GolfPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive proof that no column card is clearable")
        }
        XCTAssertNil(GolfPlanner.bestHint(in: state))
        // The position still has legal draws — the hint's nil is a verdict, not a bug.
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testExhaustedSearchYieldsExactMaxClearLine() {
        // The 2 plays on the 3; the King then blocks everything (no wrap), so
        // the exact max-clear answer is one card, proved.
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.spades, .two)],
                [TestCards.make(.hearts, .king)]
            ],
            waste: [TestCards.make(.diamonds, .three)],
            fillWasteFromRemainder: true
        )

        guard case .bestEffortLine(let line, dealIsProvedUnwinnable: true) =
                GolfPlanner.bestLine(in: state) else {
            return XCTFail("Expected a proved best-effort outcome")
        }
        XCTAssertEqual(line, [.play(column: 0)])
    }

    func testNoMovesWhenStockEmptyAndNoPlay() {
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .nine)]],
            waste: [TestCards.make(.diamonds, .six)],
            fillWasteFromRemainder: true
        )

        guard case .noProgress(searchWasExhaustive: true) = GolfPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive no-progress outcome")
        }
        XCTAssertNil(GolfPlanner.bestHint(in: state))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testStateKeyMergesOnlyStrategicallyIdenticalStates() {
        let base = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .six)]],
            stock: [TestCards.make(.clubs, .nine)],
            waste: [TestCards.make(.diamonds, .seven)]
        )

        // Buried waste history and suits are strategically inert: same key.
        var differentHistory = base
        differentHistory.waste.insert(TestCards.make(.hearts, .two), at: 0)
        XCTAssertEqual(
            GolfPlanner.stateKey(for: base),
            GolfPlanner.stateKey(for: differentHistory)
        )
        var differentSuit = base
        differentSuit.waste[0] = TestCards.make(.clubs, .seven)
        XCTAssertEqual(
            GolfPlanner.stateKey(for: base),
            GolfPlanner.stateKey(for: differentSuit)
        )

        // The waste top rank, the board, and the stock all gate the future:
        // each changes the key.
        var differentTop = base
        differentTop.waste[0] = TestCards.make(.diamonds, .eight)
        XCTAssertNotEqual(
            GolfPlanner.stateKey(for: base),
            GolfPlanner.stateKey(for: differentTop)
        )
        var differentBoard = base
        differentBoard.tableau[0] = [TestCards.make(.spades, .five, isFaceUp: true)]
        XCTAssertNotEqual(
            GolfPlanner.stateKey(for: base),
            GolfPlanner.stateKey(for: differentBoard)
        )
        var differentStock = base
        differentStock.stock = [TestCards.make(.clubs, .ten, isFaceUp: false)]
        XCTAssertNotEqual(
            GolfPlanner.stateKey(for: base),
            GolfPlanner.stateKey(for: differentStock)
        )
        // Identical cards in a different column arrangement are a different
        // position (their exposure order differs).
        var differentColumn = base
        differentColumn.tableau[0] = []
        differentColumn.tableau[1] = [TestCards.make(.spades, .six, isFaceUp: true)]
        XCTAssertNotEqual(
            GolfPlanner.stateKey(for: base),
            GolfPlanner.stateKey(for: differentColumn)
        )
    }

    func testMaterializeRejectsStaleMoves() {
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .six)]],
            waste: [TestCards.make(.diamonds, .seven)]
        )
        let move = GolfPlanner.Move.play(column: 0)
        XCTAssertNotNil(GolfPlanner.materialize(move, in: state))

        var emptiedColumn = state
        emptiedColumn.tableau[0] = []
        XCTAssertNil(
            GolfPlanner.materialize(move, in: emptiedColumn),
            "A cached move for an emptied column must not surface"
        )

        var changedTop = state
        changedTop.waste[0] = TestCards.make(.hearts, .ten)
        XCTAssertNil(
            GolfPlanner.materialize(move, in: changedTop),
            "A cached move that is no longer adjacent must not surface"
        )

        XCTAssertNil(
            GolfPlanner.materialize(.draw, in: state),
            "A draw hint with an empty stock must not surface"
        )
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must
        // report truncation — not exhaustion, which would wrongly claim the
        // deal is dead.
        let limits = GolfPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededGolfDeal(seed: 5)

        guard case .noProgress(searchWasExhaustive: false) = GolfPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(GolfPlanner.bestHint(in: state, limits: limits))
    }

    func testHintsAreAlwaysLegalFromArbitraryMidGamePositions() {
        // Planner moves must materialize into advisor-legal moves from any
        // reachable position, not just fresh deals.
        for seed in 1...5 {
            var state = GameStateFixtures.seededGolfDeal(seed: UInt64(seed))
            var generator = SeededRandomNumberGenerator(seed: UInt64(seed) &* 977)
            for _ in 0..<8 {
                var options: [(Selection, Destination)] = []
                for selection in AutoMoveAdvisor.candidateSelections(in: state) {
                    for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                        options.append((selection, destination))
                    }
                }
                if !state.stock.isEmpty, generator.next() % 2 == 0 {
                    state = GolfPlanner.apply(.draw, to: state) ?? state
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

            guard let hint = GolfPlanner.bestHint(in: state) else { continue }
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
            return GolfPlanner.apply(.draw, to: state)
        }
    }

    private func replayThroughAdvisor(_ move: GolfPlanner.Move, on state: inout GameState) {
        guard case .move(let hintMove)? = GolfPlanner.materialize(move, in: state) else {
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
