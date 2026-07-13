import XCTest
@testable import Computer_Solitaire

@MainActor
final class TriPeaksPersistenceTests: XCTestCase {
    private func payload(for state: GameState, stockDrawCount: Int = DrawMode.one.rawValue) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            stockDrawCount: stockDrawCount,
            history: []
        )
    }

    /// A legally reachable mid-game shape: two base cards played onto the waste
    /// (a two-card chain), one stock card flipped beneath them.
    private func midGameState() -> GameState {
        var state = GameStateFixtures.seededTriPeaksDeal(seed: 2)
        var drawn = state.stock.removeLast()
        drawn.isFaceUp = true
        state.waste.append(drawn)
        for slot in [27, 26] {
            var played = state.triPeaks[slot]!
            played.isFaceUp = true
            state.triPeaks[slot] = nil
            state.waste.append(played)
        }
        TriPeaksGameRules.flipNewlyUncoveredCards(in: &state)
        state.triPeaksChainLength = 2
        state.wasteDrawCount = 1
        return state
    }

    func testFreshDealRoundTripsThroughSanitization() throws {
        let state = GameState.newTriPeaksGame()
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
        XCTAssertEqual(decoded.triPeaksChainLength, 2)

        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)
        XCTAssertEqual(try XCTUnwrap(sanitized).state, state)
    }

    func testDecodingLegacySaveWithoutTriPeaksFields() throws {
        // Saves written before the TriPeaks variant carry no triPeaks keys; they
        // must decode to empty TriPeaks fields and keep validating.
        let legacy = GameStateFixtures.seededKlondikeDeal(seed: 1)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)
        ) as? [String: Any] ?? [:]
        json.removeValue(forKey: "triPeaks")
        json.removeValue(forKey: "triPeaksChainLength")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertTrue(decoded.triPeaks.isEmpty)
        XCTAssertEqual(decoded.triPeaksChainLength, 0)
        XCTAssertNotNil(payload(for: decoded, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference))
    }

    func testSanitizationAcceptsLegalMidGameStates() {
        XCTAssertNotNil(payload(for: midGameState()).sanitizedForRestore(at: DateFixtures.reference))
    }

    func testSanitizationRejectsCorruptTriPeaksStates() {
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

        assertRejected("Wrong slot count") { state in
            state.triPeaks.removeLast()
        }
        assertRejected("A removed card under an intact coverer is unreachable") { state in
            // Slot 9 is covered while base 18/19 remain on a near-fresh board.
            let card = state.triPeaks[9]!
            state.triPeaks[9] = nil
            state.waste.insert(card, at: 0)
        }
        assertRejected("A covered face-up card breaks the flip invariant") { state in
            state.triPeaks[9]?.isFaceUp = true
        }
        assertRejected("An uncovered face-down card breaks the flip invariant") { state in
            state.triPeaks[20]?.isFaceUp = false
        }
        assertRejected("Cards stranded in the pyramid field are invisible") { state in
            state.pyramid = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in the discard are invisible") { state in
            state.discard = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in a tableau pile are invisible") { state in
            state.tableau = [[state.waste.removeLast()]]
        }
        assertRejected("Cards stranded in a foundation are invisible") { state in
            state.foundations[0] = [state.waste.removeLast()]
        }
        assertRejected("Cards stranded in a free cell are invisible") { state in
            state.freeCells[0] = state.waste.removeLast()
        }
        assertRejected("TriPeaks never recycles the waste") { state in
            state.wasteRecyclesUsed = 1
        }
        assertRejected("An empty waste has no match target") { state in
            state.stock.append(contentsOf: state.waste)
            state.waste = []
            state.triPeaksChainLength = 0
        }
        assertRejected("The chain cannot exceed the waste beyond its starter") { state in
            state.triPeaksChainLength = state.waste.count
        }
        assertRejected("The chain cannot exceed the cards removed from the board") { state in
            state.triPeaksChainLength = 3
        }
        assertRejected("A negative chain is corrupt") { state in
            state.triPeaksChainLength = -1
        }
        assertRejected("Duplicate cards break deck composition") { state in
            state.waste[0] = state.waste[1]
        }
    }

    func testOtherVariantsRejectStrandedTriPeaksState() {
        var klondike = GameStateFixtures.seededKlondikeDeal(seed: 1)
        klondike.triPeaks = [klondike.stock.removeLast()]
        XCTAssertNil(
            payload(for: klondike, stockDrawCount: DrawMode.three.rawValue)
                .sanitizedForRestore(at: DateFixtures.reference),
            "A card stranded in triPeaks would be invisible in Klondike"
        )

        var pyramid = GameStateFixtures.seededPyramidDeal(seed: 1)
        pyramid.triPeaksChainLength = 2
        XCTAssertNil(
            payload(for: pyramid).sanitizedForRestore(at: DateFixtures.reference),
            "A nonzero chain outside TriPeaks is corrupt"
        )
    }

    func testSanitizationForcesTriPeaksDrawCounts() throws {
        let state = GameState.newTriPeaksGame()
        let sanitized = payload(for: state, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(
            restored.stockDrawCount,
            DrawMode.one.rawValue,
            "TriPeaks always draws a single card"
        )
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testViewModelRestoresTriPeaksPayload() throws {
        let state = midGameState()
        let viewModel = SolitaireViewModel()
        XCTAssertTrue(viewModel.restore(from: payload(for: state)))
        XCTAssertEqual(viewModel.gameVariant, .tripeaks)
        XCTAssertEqual(viewModel.state, state)
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
    }
}
