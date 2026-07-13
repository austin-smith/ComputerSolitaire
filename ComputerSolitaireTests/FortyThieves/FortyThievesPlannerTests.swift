import XCTest
@testable import Computer_Solitaire

@MainActor
final class FortyThievesPlannerTests: XCTestCase {
    func testHintIsDeterministicAcrossCalls() {
        let state = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .nine), TestCards.make(.spades, .seven)],
                [TestCards.make(.spades, .eight)],
                [TestCards.make(.clubs, .four)]
            ]
        )

        let first = FortyThievesPlanner.bestHint(in: state)
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(FortyThievesPlanner.bestHint(in: state), first)
        }
    }

    func testFreshDealsAlwaysHaveAHint() {
        // A fresh deal always has a hint through the stack: an improving line
        // when the search finds one, the stock-tap fallback otherwise (the
        // 64-card stock guarantees a legal draw).
        for seed in 1...10 {
            let state = GameStateFixtures.seededFortyThievesDeal(seed: UInt64(seed))
            XCTAssertNotNil(
                HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.one.rawValue),
                "Seed \(seed): a fresh Forty Thieves deal should always yield a hint"
            )
        }
    }

    func testHintsAreAlwaysLegalFromArbitraryMidGamePositions() {
        let limits = FortyThievesPlanner.Limits(maxNodes: 2_000)
        var generator = SeededRandomNumberGenerator(seed: 99)

        for seed in 1...5 {
            var state = GameStateFixtures.seededFortyThievesDeal(seed: UInt64(seed))
            for _ in 0..<8 {
                guard let next = randomLegalSuccessor(of: state, using: &generator) else { break }
                state = next
            }

            guard let hint = FortyThievesPlanner.bestHint(in: state, limits: limits) else { continue }
            switch hint {
            case .move(let move):
                XCTAssertTrue(AutoMoveAdvisor.selectionMatchesState(move.selection, in: state))
                XCTAssertTrue(
                    AutoMoveAdvisor.legalDestinations(for: move.selection, in: state)
                        .contains(move.destination)
                )
                XCTAssertEqual(move.selection.cards.count, 1, "Sequences never move in Forty Thieves")
                if case .foundation = move.selection.source {
                    XCTFail("A hint must never move a foundation card")
                }
            case .stockTap:
                XCTAssertFalse(state.stock.isEmpty)
            }
        }
    }

    func testFollowingPlannedLinesNeverLoops() {
        // Hints follow one cached improving line to its end before re-planning,
        // and every completed line strictly improves the anchor position — that
        // ratchet is what makes looping impossible. Within a line, positions
        // never repeat; across lines a transient revisit is survivable, but the
        // same exact layout a third time would mean the hints loop. When no
        // line exists the fallback is a single stock tap, mirroring
        // `HintPlanner`; it strictly shrinks the stock so it can never cycle.
        let limits = FortyThievesPlanner.Limits(maxNodes: 4_000)
        for seed in [11, 12] as [UInt64] {
            var state = GameStateFixtures.seededFortyThievesDeal(seed: seed)
            var visitCounts: [UInt64: Int] = [stateFingerprint(state): 1]
            var actions = 0
            func record(_ key: UInt64) -> Bool {
                let count = (visitCounts[key] ?? 0) + 1
                visitCounts[key] = count
                if count >= 3 {
                    XCTFail("Following planned lines revisited the same position twice")
                    return false
                }
                return true
            }
            while actions < 400 {
                switch FortyThievesPlanner.bestLine(in: state, limits: limits) {
                case .line(let line):
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
                        guard record(key) else { return }
                    }
                case .noProgress:
                    guard !state.stock.isEmpty,
                          let next = applied(FortyThievesPlanner.PlannedAction.stockTap, to: state) else {
                        return
                    }
                    state = next
                    actions += 1
                    guard record(stateFingerprint(state)) else { return }
                }
            }
        }
    }

    func testKeyedActionsFollowTheLineInLockstepWithTheSharedSimulation() {
        // Replaying the line through `AutoMoveAdvisor.simulatedState` must land
        // on exactly the keys `keyedActions` mapped: this pins the planner's
        // internal transition to the session's shared move algebra.
        let state = GameStateFixtures.seededFortyThievesDeal(seed: 3)
        guard case .line(let line) = FortyThievesPlanner.bestLine(
            in: state,
            limits: FortyThievesPlanner.Limits(maxNodes: 4_000)
        ) else {
            return XCTFail("Expected an improving line on a fresh deal")
        }

        let keyed = FortyThievesPlanner.keyedActions(along: line, from: state)
        XCTAssertEqual(keyed.count, line.count, "Every step along the line keys one action")

        var current = state
        for action in line {
            let key = FortyThievesPlanner.stateKey(for: current)
            guard let planned = keyed[key] else {
                return XCTFail("A followed position lost its cached action")
            }
            XCTAssertNotNil(
                FortyThievesPlanner.materialize(planned, in: current),
                "The cached action must re-validate against the live position"
            )
            guard let next = applied(action, to: current) else {
                return XCTFail("Planned action was not legal")
            }
            current = next
        }
    }

    func testMaterializeRejectsStaleActions() {
        let sevenSpades = TestCards.make(.spades, .seven)
        let state = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .nine), sevenSpades],
                [TestCards.make(.spades, .eight)]
            ]
        )
        guard let selection = AutoMoveAdvisor.candidateSelections(in: state).first(where: {
            $0.cards.first?.id == state.tableau[0][1].id
        }) else {
            return XCTFail("Expected the exposed 7♠ selection")
        }
        let action = FortyThievesPlanner.PlannedAction.move(
            selection: selection,
            destination: .tableau(1)
        )
        XCTAssertNotNil(FortyThievesPlanner.materialize(action, in: state))

        // The same action goes stale once the card has moved away…
        var moved = state
        let card = moved.tableau[0].removeLast()
        moved.tableau[1].append(card)
        XCTAssertNil(FortyThievesPlanner.materialize(action, in: moved))

        // …or once the destination stopped accepting it.
        var blocked = state
        blocked.tableau[1].append(TestCards.make(.clubs, .two))
        XCTAssertNil(FortyThievesPlanner.materialize(action, in: blocked))

        // A stock tap is stale once the stock is out.
        XCTAssertNil(FortyThievesPlanner.materialize(.stockTap, in: state))
    }

    func testTruncatedSearchReportsNoProgressWithoutClaimingProof() {
        // A one-node budget cannot explore a fresh deal, so the search must
        // report truncation — not exhaustion, which would wrongly claim the
        // position is stuck — and the planner yields no unverified nudge.
        let limits = FortyThievesPlanner.Limits(maxNodes: 1)
        let state = GameStateFixtures.seededFortyThievesDeal(seed: 5)

        guard case .noProgress(searchWasExhaustive: false) = FortyThievesPlanner.bestLine(
            in: state,
            limits: limits
        ) else {
            return XCTFail("Expected a truncated no-progress outcome")
        }
        XCTAssertNil(FortyThievesPlanner.bestHint(in: state, limits: limits))
    }

    func testNoHintEverMovesAFoundationCard() {
        // A rollback would join the 6♠ onto the 7♠, but foundations are
        // locked; whatever the planner suggests, it must not be the 7♠ coming
        // back down.
        let state = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.spades, .six)],
                [TestCards.make(.spades, .eight)],
                [TestCards.make(.hearts, .four)]
            ],
            foundations: [
                Rank.allCases.filter { $0.rawValue <= 7 }.map { TestCards.make(.spades, $0) }
            ]
        )

        if case .move(let move)? = FortyThievesPlanner.bestHint(in: state) {
            if case .foundation = move.selection.source {
                XCTFail("A hint must never move a foundation card")
            }
        }
    }

    func testStockTapHintWhenStockNonemptyAndNothingBetter() {
        // No same-suit adjacency, no empty column, no waste play, and only
        // unplayable kings left in the stock: no improving line exists, so the
        // hint stack must point at the stock — the only way forward.
        let state = stuckBoard(
            stock: [TestCards.make(.diamonds, .king), TestCards.make(.hearts, .king)]
        )

        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state))
        XCTAssertEqual(
            HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.one.rawValue),
            .stockTap
        )
    }

    func testDeadlockedStateReturnsNilAndReportsNoMoves() {
        let state = stuckBoard(stock: [])

        XCTAssertNil(FortyThievesPlanner.bestHint(in: state))
        XCTAssertNil(HintPlanner().bestHint(in: state, stockDrawCount: DrawMode.one.rawValue))
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    func testHintPrefersUnburyingNeededCardOverNeutralShuffle() {
        // Moving the 9♥ onto the 10♥ uncovers the 5♠ the spade foundation
        // needs next; hopping the 7♦ onto the 8♦ forms a pair but digs out
        // nothing (base cards keep either move from opening a column). The
        // hint should start the unburying line.
        let nineHearts = TestCards.make(.hearts, .nine)
        let state = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.spades, .five), nineHearts],
                [TestCards.make(.diamonds, .queen), TestCards.make(.hearts, .ten)],
                [TestCards.make(.clubs, .queen), TestCards.make(.diamonds, .seven)],
                [TestCards.make(.spades, .jack), TestCards.make(.diamonds, .eight)]
            ],
            foundations: [
                Rank.allCases.filter { $0.rawValue <= 4 }.map { TestCards.make(.spades, $0) }
            ]
        )

        guard case .move(let move)? = FortyThievesPlanner.bestHint(in: state) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineHearts.id)
        XCTAssertEqual(move.destination, .tableau(1))
    }

    func testHintTargetsTheFirstEmptyColumnAndTheFirstTwinDestination() {
        // Emptying onto interchangeable landings is canonicalized: with two
        // empty columns the hint points at the first, and with twin 8♠ tops it
        // points at the lower-indexed column.
        let nineHearts = TestCards.make(.hearts, .nine)
        let emptyColumnBoard = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.spades, .ace), nineHearts],
                [TestCards.make(.clubs, .five), TestCards.make(.diamonds, .two)],
                [TestCards.make(.clubs, .jack), TestCards.make(.diamonds, .queen)]
            ]
        )
        guard case .move(let move)? = FortyThievesPlanner.bestHint(in: emptyColumnBoard) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(move.selection.cards.first?.id, nineHearts.id)
        XCTAssertEqual(move.destination, .tableau(3), "Drops canonicalize to the first empty column")

        let sevenSpades = TestCards.make(.spades, .seven)
        let twinBoard = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .four), sevenSpades],
                [TestCards.make(.diamonds, .nine), TestCards.make(.spades, .eight)],
                [TestCards.make(.clubs, .nine), TestCards.make(.spades, .eight)],
                [TestCards.make(.hearts, .jack), TestCards.make(.hearts, .queen)],
                [TestCards.make(.clubs, .jack), TestCards.make(.clubs, .queen)],
                [TestCards.make(.diamonds, .jack), TestCards.make(.diamonds, .queen)],
                [TestCards.make(.spades, .jack), TestCards.make(.spades, .queen)],
                [TestCards.make(.hearts, .two), TestCards.make(.clubs, .four)],
                [TestCards.make(.diamonds, .three), TestCards.make(.hearts, .six)],
                [TestCards.make(.clubs, .three), TestCards.make(.diamonds, .six)]
            ]
        )
        guard case .move(let twinMove)? = FortyThievesPlanner.bestHint(in: twinBoard) else {
            return XCTFail("Expected a move hint")
        }
        XCTAssertEqual(twinMove.selection.cards.first?.id, sevenSpades.id)
        XCTAssertEqual(twinMove.destination, .tableau(1), "Twin tops canonicalize to the lower column")
    }

    func testBankingLineIsFoundAndCachedEndToEnd() {
        // Every foundation is one Queen-and-King away from completion; the
        // HintPlanner's cached line must walk the whole mop-up to the win
        // without a single nil hint.
        let foundations = Suit.allCases.flatMap { suit in
            (0..<2).map { _ in
                Rank.allCases.filter { $0.rawValue <= 11 }.map { TestCards.make(suit, $0) }
            }
        }
        let columns = Suit.allCases.flatMap { suit in
            (0..<2).map { _ in
                [TestCards.make(suit, .king), TestCards.make(suit, .queen)]
            }
        }
        var state = GameStateFixtures.fortyThievesState(
            columns: columns,
            foundations: foundations
        )
        XCTAssertNotNil(
            SavedGamePayload(state: state, movesCount: 0, score: 0, stockDrawCount: DrawMode.one.rawValue, history: [])
                .sanitizedForRestore(at: DateFixtures.reference),
            "The mop-up must be a legal 104-card position"
        )

        let planner = HintPlanner()
        var actions = 0
        while actions < 40 {
            if state.isWon {
                return
            }
            guard let hint = planner.bestHint(in: state, stockDrawCount: DrawMode.one.rawValue) else {
                return XCTFail("Hint stack gave up after \(actions) actions")
            }
            guard let next = applied(hint, to: state) else {
                return XCTFail("Hinted action was not legal after \(actions) actions")
            }
            state = next
            actions += 1
        }
        XCTFail("Did not win within 40 actions")
    }

    // MARK: - Helpers

    /// Ten columns with no same-suit adjacency, no empty column, no waste,
    /// and empty foundations: no tableau or waste action is legal.
    private func stuckBoard(stock: [Card]) -> GameState {
        var columns = Suit.allCases.flatMap { suit in
            [
                [TestCards.make(.hearts, .queen), TestCards.make(suit, .three)],
                [TestCards.make(.clubs, .queen), TestCards.make(suit, .three)]
            ]
        }
        columns.append([TestCards.make(.hearts, .queen), TestCards.make(.spades, .eight)])
        columns.append([TestCards.make(.clubs, .queen), TestCards.make(.spades, .eight)])
        return GameStateFixtures.fortyThievesState(columns: columns, stock: stock)
    }

    private func applied(_ hint: HintAdvisor.Hint, to state: GameState) -> GameState? {
        switch hint {
        case .move(let move):
            return AutoMoveAdvisor.simulatedState(
                afterMoving: move.selection,
                to: move.destination,
                in: state,
                stockDrawCount: DrawMode.one.rawValue
            )
        case .stockTap:
            return applied(FortyThievesPlanner.PlannedAction.stockTap, to: state)
        }
    }

    private func applied(
        _ action: FortyThievesPlanner.PlannedAction,
        to state: GameState
    ) -> GameState? {
        switch action {
        case .move(let selection, let destination):
            return AutoMoveAdvisor.simulatedState(
                afterMoving: selection,
                to: destination,
                in: state,
                stockDrawCount: DrawMode.one.rawValue
            )
        case .stockTap:
            guard !state.stock.isEmpty else { return nil }
            var next = state
            var card = next.stock.removeLast()
            card.isFaceUp = true
            next.waste.append(card)
            next.wasteDrawCount = 1
            return next
        }
    }

    private func randomLegalSuccessor(
        of state: GameState,
        using generator: inout SeededRandomNumberGenerator
    ) -> GameState? {
        var moves: [(Selection, Destination)] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                moves.append((selection, destination))
            }
        }
        let actionCount = moves.count + (state.stock.isEmpty ? 0 : 1)
        guard actionCount > 0 else { return nil }
        let pick = Int(generator.next() % UInt64(actionCount))
        if pick == moves.count {
            return applied(FortyThievesPlanner.PlannedAction.stockTap, to: state)
        }
        let (selection, destination) = moves[pick]
        return AutoMoveAdvisor.simulatedState(
            afterMoving: selection,
            to: destination,
            in: state,
            stockDrawCount: DrawMode.one.rawValue
        )
    }

    private func stateFingerprint(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) { hash = (hash ^ UInt64(value)) &* 0x100000001b3 }
        func mix(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            mix(UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0)))
        }
        mix(UInt8(state.stock.count))
        mix(0xFC)
        for card in state.waste { mix(card: card) }
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
