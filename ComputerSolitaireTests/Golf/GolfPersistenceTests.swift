import XCTest
@testable import Computer_Solitaire

@MainActor
final class GolfPersistenceTests: XCTestCase {
    private func payload(
        for state: GameState,
        score: Int = 0,
        stockDrawCount: Int = DrawMode.one.rawValue
    ) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            score: score,
            stockDrawCount: stockDrawCount,
            history: []
        )
    }

    /// A legally reachable mid-game shape: one stock card flipped, then two
    /// column cards played onto the waste.
    private func midGameState() -> GameState {
        var state = GameStateFixtures.seededGolfDeal(seed: 2)
        var drawn = state.stock.removeLast()
        drawn.isFaceUp = true
        state.waste.append(drawn)
        for column in [0, 3] {
            let played = state.tableau[column].removeLast()
            state.waste.append(played)
        }
        state.wasteDrawCount = 1
        return state
    }

    func testFreshDealRoundTripsThroughSanitization() throws {
        let state = GameState.newGolfGame()
        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(restored.state, state)
        XCTAssertEqual(restored.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testMidGameStateSurvivesEncodeDecode() throws {
        let state = midGameState()

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, state)

        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)
        XCTAssertEqual(try XCTUnwrap(sanitized).state, state)
    }

    func testNegativeGolfScoreSurvivesSanitizationWhileOthersClamp() throws {
        // A cleared Golf board with leftover stock ends below zero; the
        // sanitizer must preserve that for Golf and keep flooring everyone else.
        var wonState = GameStateFixtures.golfState(
            columns: [],
            stock: [TestCards.make(.clubs, .nine), TestCards.make(.hearts, .two)],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        wonState.wasteDrawCount = 1
        let golfPayload = payload(for: wonState, score: -2)
        let restoredGolf = try XCTUnwrap(golfPayload.sanitizedForRestore(at: DateFixtures.reference))
        XCTAssertEqual(restoredGolf.score, -2, "A negative Golf score is a legal result")

        let klondike = GameStateFixtures.seededKlondikeDeal(seed: 1)
        let klondikePayload = payload(
            for: klondike,
            score: -2,
            stockDrawCount: DrawMode.three.rawValue
        )
        let restoredKlondike = try XCTUnwrap(
            klondikePayload.sanitizedForRestore(at: DateFixtures.reference)
        )
        XCTAssertEqual(restoredKlondike.score, 0, "Non-Golf scores still floor at zero")
    }

    func testDecodingLegacySaveKeepsValidating() throws {
        // Saves written before the Golf variant decode unchanged; Golf reuses
        // the tableau/stock/waste fields, so no new GameState keys exist to
        // go missing.
        let legacy = GameStateFixtures.seededKlondikeDeal(seed: 1)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertNotNil(
            payload(for: decoded, stockDrawCount: DrawMode.three.rawValue)
                .sanitizedForRestore(at: DateFixtures.reference)
        )
    }

    func testSanitizationAcceptsLegalMidGameStates() {
        XCTAssertNotNil(payload(for: midGameState()).sanitizedForRestore(at: DateFixtures.reference))
    }

    func testSanitizationRejectsCorruptGolfStates() {
        func assertRejected(
            _ message: String,
            mutate: (inout GameState) -> Void
        ) {
            var state = midGameState()
            mutate(&state)
            XCTAssertNil(
                payload(for: state).sanitizedForRestore(at: DateFixtures.reference),
                message
            )
        }

        assertRejected("Wrong column count") { state in
            state.tableau.removeLast()
        }
        assertRejected("A six-card column exceeds the deal") { state in
            let card = state.waste.removeLast()
            state.tableau[6].append(card)
        }
        assertRejected("A face-down board card breaks the all-face-up invariant") { state in
            state.tableau[1][0].isFaceUp = false
        }
        assertRejected("A face-up stock card breaks the stock invariant") { state in
            state.stock[0].isFaceUp = true
        }
        assertRejected("A stock beyond sixteen cards exceeds the deal") { state in
            // The mid-game stock holds fifteen; adding two crosses the deal's
            // sixteen-card ceiling.
            for _ in 0..<2 {
                var card = state.waste.removeFirst()
                card.isFaceUp = false
                state.stock.append(card)
            }
        }
        assertRejected("Cards stranded in the pyramid field are invisible") { state in
            state.pyramid = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in the triPeaks field are invisible") { state in
            state.triPeaks = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in the discard are invisible") { state in
            state.discard = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in a foundation are invisible") { state in
            state.foundations[0] = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in a free cell are invisible") { state in
            state.freeCells[0] = state.waste.removeLast()
        }
        assertRejected("Golf never recycles the waste") { state in
            state.wasteRecyclesUsed = 1
        }
        assertRejected("Duplicate cards break deck composition") { state in
            state.waste[0] = state.waste[1]
        }
    }

    func testLayoutRuleRejectsEmptyWasteAndWrongWasteDrawCount() {
        // A full 52-card state cannot isolate these guards (the waste starter
        // has nowhere else legal to live), so the layout rule is checked
        // directly as defense in depth.
        var state = midGameState()
        state.waste = []
        XCTAssertFalse(
            GolfPersistenceRules.hasValidLayout(state: state),
            "An empty waste has no match target"
        )

        state = midGameState()
        state.wasteDrawCount = 3
        XCTAssertFalse(
            GolfPersistenceRules.hasValidLayout(state: state),
            "Golf always shows a single waste card"
        )
    }

    func testOtherVariantsRejectStrandedGolfShapedTableau() {
        // Golf reuses the shared tableau, so the guard here is the reverse:
        // a Golf save must reject cards stranded in the other variants' fields,
        // and a Golf state under another variant's rules fails that variant's
        // layout validation.
        var state = midGameState()
        state.variant = .tripeaks
        XCTAssertNil(
            payload(for: state).sanitizedForRestore(at: DateFixtures.reference),
            "A Golf board is not a valid TriPeaks layout"
        )
    }

    func testSanitizationForcesGolfDrawCounts() throws {
        let state = GameState.newGolfGame()
        let sanitized = payload(for: state, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(
            restored.stockDrawCount,
            DrawMode.one.rawValue,
            "Golf always draws a single card"
        )
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testViewModelRestoresGolfPayload() throws {
        let state = midGameState()
        let viewModel = SolitaireViewModel()
        XCTAssertTrue(viewModel.restore(from: payload(for: state)))
        XCTAssertEqual(viewModel.gameVariant, .golf)
        XCTAssertEqual(viewModel.state, state)
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
    }
}
