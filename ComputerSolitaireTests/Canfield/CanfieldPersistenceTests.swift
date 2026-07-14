import XCTest
@testable import Computer_Solitaire

@MainActor
final class CanfieldPersistenceTests: XCTestCase {
    private func payload(
        for state: GameState,
        score: Int = 0,
        stockDrawCount: Int = DrawMode.three.rawValue
    ) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            score: score,
            stockDrawCount: stockDrawCount,
            history: []
        )
    }

    /// A mid-game shape: one three-card turn onto the waste — the 52-card
    /// census stays intact and every dealt invariant still holds.
    private func midGameState() -> GameState {
        var state = GameStateFixtures.seededCanfieldDeal(seed: 2)
        for _ in 0..<3 {
            var drawn = state.stock.removeLast()
            drawn.isFaceUp = true
            state.waste.append(drawn)
        }
        state.wasteDrawCount = 3
        return state
    }

    func testFreshDealRoundTripsThroughSanitization() throws {
        let state = GameState.newCanfieldGame()
        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(restored.state, state)
        XCTAssertEqual(restored.stockDrawCount, DrawMode.three.rawValue)
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

    func testDecodingAPayloadWithoutAReserveDefaultsToEmpty() throws {
        // Saves written before the reserve existed carry no key for it.
        var state = GameStateFixtures.seededKlondikeDeal(seed: 4)
        state.variant = .klondike
        let data = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var stripped = object
        stripped.removeValue(forKey: "reserve")
        let strippedData = try JSONSerialization.data(withJSONObject: stripped)

        let decoded = try JSONDecoder().decode(GameState.self, from: strippedData)
        XCTAssertTrue(decoded.reserve.isEmpty)
    }

    func testSanitizationFloorsTheFanAtOneWhileTheWasteHolds() throws {
        // A save that buries a non-empty waste (fan count zero) predates the
        // always-available rule or is corrupt; the sanitizer repairs it so the
        // restored game keeps its waste top playable.
        var state = midGameState()
        state.wasteDrawCount = 0
        let sanitized = try XCTUnwrap(
            payload(for: state).sanitizedForRestore(at: DateFixtures.reference)
        )
        XCTAssertEqual(sanitized.state.wasteDrawCount, 1)
    }

    func testSanitizationForcesCanfieldDrawCounts() throws {
        let state = GameState.newCanfieldGame()
        let sanitized = payload(for: state, stockDrawCount: DrawMode.one.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(
            restored.stockDrawCount,
            DrawMode.three.rawValue,
            "Canfield always turns three"
        )
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testSanitizationRejectsCorruptCanfieldStates() {
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

        assertRejected("Wrong pile count") { state in
            state.tableau.removeLast()
        }
        assertRejected("Wrong foundation count") { state in
            state.foundations.removeLast()
        }
        assertRejected("A face-down tableau card breaks the all-face-up invariant") { state in
            state.tableau[1][0].isFaceUp = false
        }
        assertRejected("A face-up stock card breaks the stock invariant") { state in
            state.stock[0].isFaceUp = true
        }
        assertRejected("A face-down reserve top breaks the reserve invariant") { state in
            state.reserve[state.reserve.count - 1].isFaceUp = false
        }
        assertRejected("A second face-up reserve card breaks the reserve invariant") { state in
            state.reserve[0].isFaceUp = true
        }
        assertRejected("A reserve beyond thirteen cards exceeds the deal") { state in
            var card = state.waste.removeLast()
            card.isFaceUp = false
            state.reserve.insert(card, at: 0)
            state.wasteDrawCount = 2
        }
        assertRejected("A space must not persist while the reserve holds cards") { state in
            var card = state.tableau[0].removeLast()
            card.isFaceUp = true
            state.waste.append(card)
        }
        assertRejected("An unseeded board has no base rank") { state in
            state.waste.append(contentsOf: state.foundations[0])
            state.foundations[0] = []
            state.wasteDrawCount = 3
        }
        assertRejected("A missing card breaks deck composition") { state in
            state.tableau[2].removeLast()
        }
        assertRejected("A duplicate identity breaks deck composition") { state in
            let copied = state.tableau[1][0]
            state.tableau[2][0] = TestCards.make(copied.suit, copied.rank)
        }
        assertRejected("Cards stranded in a free cell are invisible") { state in
            state.freeCells[0] = state.waste.removeLast()
            state.wasteDrawCount = 2
        }
        assertRejected("Cards stranded in the pyramid field are invisible") { state in
            state.pyramid = [state.waste.removeLast()]
            state.wasteDrawCount = 2
        }
        assertRejected("Canfield recycles are deliberately untracked") { state in
            state.wasteRecyclesUsed = 1
        }
    }

    func testLayoutRuleChecksFoundationRuns() {
        // Census-independent checks against the layout rule directly: a
        // foundation grows one suit upward from the base rank, turning the
        // corner, or it is corrupt.
        let offSuitRun = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [[TestCards.make(.spades, .nine), TestCards.make(.hearts, .ten)]]
        )
        XCTAssertFalse(CanfieldPersistenceRules.hasValidLayout(state: offSuitRun))

        let skippedRank = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [[TestCards.make(.spades, .nine), TestCards.make(.spades, .jack)]]
        )
        XCTAssertFalse(CanfieldPersistenceRules.hasValidLayout(state: skippedRank))

        let mismatchedBase = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [
                [TestCards.make(.spades, .nine)],
                [TestCards.make(.hearts, .ten)]
            ]
        )
        XCTAssertFalse(
            CanfieldPersistenceRules.hasValidLayout(state: mismatchedBase),
            "Every foundation starts at the same base rank"
        )

        let wrappedRun = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [[
                TestCards.make(.spades, .queen),
                TestCards.make(.spades, .king),
                TestCards.make(.spades, .ace)
            ]]
        )
        XCTAssertTrue(
            CanfieldPersistenceRules.hasValidLayout(state: wrappedRun),
            "A run turning the corner from King to Ace is the rule, not corruption"
        )
    }

    func testLayoutRuleChecksPackedTableauPiles() {
        let unpacked = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.spades, .eight), TestCards.make(.clubs, .seven)]],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        XCTAssertFalse(
            CanfieldPersistenceRules.hasValidLayout(state: unpacked),
            "A same-color join can never have been dealt or played"
        )

        let wrappedPile = GameStateFixtures.canfieldState(
            columns: [[
                TestCards.make(.spades, .two),
                TestCards.make(.hearts, .ace),
                TestCards.make(.clubs, .king)
            ]],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        XCTAssertTrue(CanfieldPersistenceRules.hasValidLayout(state: wrappedPile))
    }

    func testViewModelRestoresCanfieldPayload() throws {
        let state = midGameState()
        let viewModel = SolitaireViewModel()
        XCTAssertTrue(viewModel.restore(from: payload(for: state)))
        XCTAssertEqual(viewModel.gameVariant, .canfield)
        XCTAssertEqual(viewModel.gameMode, .canfield)
        XCTAssertEqual(viewModel.state, state)
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.three.rawValue)
    }
}
