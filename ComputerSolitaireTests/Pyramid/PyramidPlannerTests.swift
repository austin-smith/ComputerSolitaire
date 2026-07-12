import XCTest
@testable import Computer_Solitaire

@MainActor
final class PyramidPlannerTests: XCTestCase {
    // Probe-verified seeds (release-build probe study over seeded deals): the
    // winning seed's deal is cleared by following hints end-to-end; the unwinnable
    // seed is proved lost by the exhaustive stage-one search at the default budget.
    private static let winningSeed: UInt64 = 1
    private static let unwinnableSeed: UInt64 = 42

    func testHintIsDeterministicAcrossCalls() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .seven)
        slots[23] = TestCards.make(.clubs, .king)
        let state = GameStateFixtures.pyramidState(slots: slots)

        let first = PyramidPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(PyramidPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal always has clearable cards within easy reach, so a small
        // budget keeps the suite fast; production searches are capped by the
        // interactive deadline.
        let limits = PyramidPlanner.Limits(maxNodes: 20_000)
        for seed in 1...10 {
            let state = GameStateFixtures.seededPyramidDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                PyramidPlanner.bestHint(in: state, limits: limits),
                "Seed \(seed): a fresh Pyramid deal should have a suggestible line"
            )
        }
    }

    func testWinningLineReplaysLegallyToAClearedPyramid() {
        let state = GameStateFixtures.seededPyramidDeal(seed: Self.winningSeed)
        guard case .winningLine(let line) = PyramidPlanner.bestLine(in: state) else {
            return XCTFail("Probe-verified winning seed should produce a winning line")
        }

        var current = state
        for move in line {
            if case .removePair = move {
                replayThroughAdvisor(move, on: &current)
            } else if case .removeKing = move {
                replayThroughAdvisor(move, on: &current)
            } else {
                guard let next = PyramidPlanner.apply(move, to: current) else {
                    return XCTFail("Stock move in the winning line was not legal")
                }
                current = next
            }
        }
        XCTAssertTrue(current.isWon, "Replaying the winning line must clear the pyramid")
    }

    func testKeyedMovesFollowTheSolutionLine() {
        let state = GameStateFixtures.seededPyramidDeal(seed: Self.winningSeed)
        guard case .winningLine(let line) = PyramidPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line")
        }

        let keyed = PyramidPlanner.keyedMoves(along: line, from: state)
        XCTAssertEqual(keyed.count, line.count, "Every position along the line gets its move")

        var current = state
        for move in line {
            XCTAssertEqual(keyed[PyramidPlanner.stateKey(for: current)], move)
            guard let next = PyramidPlanner.apply(move, to: current) else {
                return XCTFail("Line move was not legal")
            }
            current = next
        }
    }

    func testHintPlannerWinsAKnownDealEndToEnd() {
        // Probe-verified winning seed: following the HintPlanner's cached lines
        // (including stock taps) plays this deal to a win. Guards the whole stack.
        let planner = HintPlanner()
        var state = GameStateFixtures.seededPyramidDeal(seed: Self.winningSeed)
        var steps = 0

        while steps < 200 {
            if state.isWon {
                return
            }
            guard let hint = planner.bestHint(in: state, stockDrawCount: 1) else {
                return XCTFail("Hint stack gave up after \(steps) steps")
            }
            switch hint {
            case .move(let move):
                guard let next = AutoMoveAdvisor.simulatedState(
                    afterMoving: move.selection,
                    to: move.destination,
                    in: state,
                    stockDrawCount: 1
                ) else {
                    return XCTFail("Hinted move was not legal after \(steps) steps")
                }
                state = next
            case .stockTap:
                let stockMove: PyramidPlanner.Move = state.stock.isEmpty ? .resetStock : .draw
                guard let next = PyramidPlanner.apply(stockMove, to: state) else {
                    return XCTFail("Hinted stock tap was not legal after \(steps) steps")
                }
                state = next
            }
            steps += 1
        }
        XCTFail("Did not win within 200 steps")
    }

    func testUnwinnableDealIsProvedAndStillYieldsBestEffortHints() {
        var state = GameStateFixtures.seededPyramidDeal(seed: Self.unwinnableSeed)
        guard case .bestEffortLine(let line, let dealIsProvedUnwinnable) =
                PyramidPlanner.bestLine(in: state) else {
            return XCTFail("Probe-verified lost seed should produce a best-effort line")
        }
        XCTAssertTrue(dealIsProvedUnwinnable, "Stage one must prove this deal lost")
        XCTAssertFalse(line.isEmpty)

        // Following hints clears strictly more cards, never plays an illegal move,
        // and ends in silence rather than churn.
        let planner = HintPlanner()
        let clearedAtStart = state.pyramid.filter { $0 == nil }.count
        var steps = 0
        while steps < 200, let hint = planner.bestHint(in: state, stockDrawCount: 1) {
            switch hint {
            case .move(let move):
                guard let next = AutoMoveAdvisor.simulatedState(
                    afterMoving: move.selection,
                    to: move.destination,
                    in: state,
                    stockDrawCount: 1
                ) else {
                    return XCTFail("Hinted move was not legal after \(steps) steps")
                }
                state = next
            case .stockTap:
                let stockMove: PyramidPlanner.Move = state.stock.isEmpty ? .resetStock : .draw
                guard let next = PyramidPlanner.apply(stockMove, to: state) else {
                    return XCTFail("Hinted stock tap was not legal after \(steps) steps")
                }
                state = next
            }
            steps += 1
        }
        XCTAssertLessThan(steps, 200, "Hints on a lost deal must eventually go silent")
        XCTAssertFalse(state.isWon)
        XCTAssertGreaterThan(
            state.pyramid.filter { $0 == nil }.count,
            clearedAtStart,
            "Best-effort hints should still clear pyramid cards"
        )
    }

    func testFollowingHintsNeverRepeatsAPosition() {
        // Every Pyramid move advances a monotone quantity, so followed lines can
        // never revisit a position; this guards the state mapping and cache.
        for seed in [Self.winningSeed, Self.unwinnableSeed] {
            let planner = HintPlanner()
            var state = GameStateFixtures.seededPyramidDeal(seed: seed)
            var seen: Set<String> = [PyramidPlanner.stateKey(for: state)]
            var steps = 0
            while steps < 200, !state.isWon,
                  let hint = planner.bestHint(in: state, stockDrawCount: 1) {
                switch hint {
                case .move(let move):
                    guard let next = AutoMoveAdvisor.simulatedState(
                        afterMoving: move.selection,
                        to: move.destination,
                        in: state,
                        stockDrawCount: 1
                    ) else {
                        return XCTFail("Hinted move was not legal")
                    }
                    state = next
                case .stockTap:
                    let stockMove: PyramidPlanner.Move = state.stock.isEmpty ? .resetStock : .draw
                    guard let next = PyramidPlanner.apply(stockMove, to: state) else {
                        return XCTFail("Hinted stock tap was not legal")
                    }
                    state = next
                }
                steps += 1
                XCTAssertTrue(
                    seen.insert(PyramidPlanner.stateKey(for: state)).inserted,
                    "Seed \(seed): following hints revisited a position"
                )
            }
        }
    }

    func testCoverPairIsSuggestedWhenItIsTheOnlyClearingMove() {
        // The 6's only remaining cover is the exposed 7: removing both together is
        // the only move that clears cards.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .six)
        slots[21] = TestCards.make(.spades, .seven)
        let state = GameStateFixtures.pyramidState(slots: slots, passesUsed: 2)

        guard case .move(let move)? = PyramidPlanner.bestHint(in: state) else {
            return XCTFail("Expected the cover-pair move hint")
        }
        XCTAssertEqual(move.selection.source, .pyramid(index: 15))
        XCTAssertEqual(move.destination, .pyramid(21))
    }

    func testResetHintWhenTheWinNeedsAnotherPass() {
        // The 6's partner sits at the bottom of the spent waste; the only winning
        // line is reset → draw → pair, so the hint is a stock tap.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        let state = GameStateFixtures.pyramidState(
            slots: slots,
            waste: [TestCards.make(.hearts, .seven), TestCards.make(.clubs, .nine)],
            passesUsed: 1
        )

        guard case .winningLine(let line) = PyramidPlanner.bestLine(in: state) else {
            return XCTFail("Expected a winning line through the reset")
        }
        XCTAssertEqual(line.first, .resetStock)
        XCTAssertEqual(PyramidPlanner.bestHint(in: state), .stockTap)
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testNoMovesWhenPassesAreExhausted() {
        // Same position with no recycles left: nothing is legal at all.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        let state = GameStateFixtures.pyramidState(
            slots: slots,
            waste: [TestCards.make(.hearts, .seven), TestCards.make(.clubs, .nine)],
            passesUsed: 2
        )

        guard case .noProgress(searchWasExhaustive: true) = PyramidPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive no-progress outcome")
        }
        XCTAssertNil(PyramidPlanner.bestHint(in: state))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must report
        // truncation — not exhaustion, which would wrongly claim the deal is dead.
        let limits = PyramidPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededPyramidDeal(seed: 5)

        guard case .noProgress(searchWasExhaustive: false) = PyramidPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(PyramidPlanner.bestHint(in: state, limits: limits))
    }

    func testProvablyFutilePositionGetsNoHintButKeepsButtonAlive() {
        // A draw is legal, but the lone 6 has no 7 anywhere: churning the stock is
        // provably futile, so the hint goes silent while the button stays alive.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        let state = GameStateFixtures.pyramidState(
            slots: slots,
            stock: [TestCards.make(.clubs, .nine), TestCards.make(.diamonds, .two)],
            passesUsed: 2
        )

        guard case .noProgress(searchWasExhaustive: true) = PyramidPlanner.bestLine(in: state) else {
            return XCTFail("Expected an exhaustive no-progress outcome")
        }
        XCTAssertNil(HintPlanner().bestHint(in: state, stockDrawCount: 1))
        // The position still has legal draws — the hint's nil is a verdict, not a bug.
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testHintsAreAlwaysLegalFromArbitraryMidGamePositions() {
        // Planner moves must materialize into advisor-legal moves from any
        // reachable position, not just fresh deals.
        for seed in 1...5 {
            var state = GameStateFixtures.seededPyramidDeal(seed: UInt64(seed))
            var generator = SeededRandomNumberGenerator(seed: UInt64(seed) &* 977)
            for _ in 0..<8 {
                var options: [(Selection, Destination)] = []
                for selection in AutoMoveAdvisor.candidateSelections(in: state) {
                    for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                        options.append((selection, destination))
                    }
                }
                if !state.stock.isEmpty, generator.next() % 2 == 0 {
                    state = PyramidPlanner.apply(.draw, to: state) ?? state
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

            guard let hint = PyramidPlanner.bestHint(in: state) else { continue }
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
                XCTAssertTrue(
                    !state.stock.isEmpty || PyramidGameRules.canRecycleWaste(in: state),
                    "Seed \(seed): stock tap hinted with a dead stock"
                )
            }
        }
    }

    // MARK: - Helpers

    private func replayThroughAdvisor(_ move: PyramidPlanner.Move, on state: inout GameState) {
        guard case .move(let hintMove)? = PyramidPlanner.materialize(move, in: state) else {
            return XCTFail("Removal move failed to materialize")
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
