import XCTest
@testable import Computer_Solitaire

@MainActor
final class PyramidPersistenceTests: XCTestCase {
    private func payload(for state: GameState, stockDrawCount: Int = DrawMode.one.rawValue) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            stockDrawCount: stockDrawCount,
            history: []
        )
    }

    func testFreshDealRoundTripsThroughSanitization() throws {
        let state = GameState.newPyramidGame()
        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)

        let restored = try XCTUnwrap(sanitized)
        XCTAssertEqual(restored.state, state)
        XCTAssertEqual(restored.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testMidGameStateSurvivesEncodeDecode() throws {
        // A legally reachable mid-game shape: two bottom-row cards removed to the
        // discard, one card drawn to the waste, one recycle spent.
        var state = GameStateFixtures.seededPyramidDeal(seed: 2)
        state.discard.append(state.pyramid[27]!)
        state.pyramid[27] = nil
        state.discard.append(state.pyramid[26]!)
        state.pyramid[26] = nil
        var drawn = state.stock.removeLast()
        drawn.isFaceUp = true
        state.waste.append(drawn)
        state.wasteDrawCount = 1
        state.wasteRecyclesUsed = 1

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, state)

        let sanitized = payload(for: state).sanitizedForRestore(at: DateFixtures.reference)
        XCTAssertEqual(try XCTUnwrap(sanitized).state, state)
    }

    func testDecodingLegacySaveWithoutPyramidFields() throws {
        // Saves written before the Pyramid variant carry no pyramid keys; they must
        // decode to empty pyramid fields.
        let legacy = GameStateFixtures.seededKlondikeDeal(seed: 1)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)
        ) as? [String: Any] ?? [:]
        json.removeValue(forKey: "pyramid")
        json.removeValue(forKey: "discard")
        json.removeValue(forKey: "wasteRecyclesUsed")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertTrue(decoded.pyramid.isEmpty)
        XCTAssertTrue(decoded.discard.isEmpty)
        XCTAssertEqual(decoded.wasteRecyclesUsed, 0)
        XCTAssertEqual(decoded.tableau, legacy.tableau)
    }

    func testLayoutValidationAcceptsLegalStatesOnly() {
        XCTAssertTrue(PyramidPersistenceRules.hasValidLayout(state: GameState.newPyramidGame()))

        // Wrong slot count.
        var truncated = GameState.newPyramidGame()
        truncated.pyramid.removeLast()
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: truncated))

        // A removed slot beneath an occupied cover breaks the removal invariant.
        var brokenCover = GameState.newPyramidGame()
        brokenCover.discard.append(brokenCover.pyramid[15]!)
        brokenCover.pyramid[15] = nil
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: brokenCover))

        // Recycle counter out of range.
        var overRecycled = GameState.newPyramidGame()
        overRecycled.wasteRecyclesUsed = PyramidGameRules.maxWasteRecycles + 1
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: overRecycled))

        // Pyramid renders no tableau, free cells, or foundations.
        var strandedTableau = GameState.newPyramidGame()
        strandedTableau.tableau = [[strandedTableau.stock.removeLast()]]
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: strandedTableau))

        var strandedFreeCell = GameState.newPyramidGame()
        strandedFreeCell.freeCells[0] = strandedFreeCell.stock.removeLast()
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: strandedFreeCell))

        var strandedFoundation = GameState.newPyramidGame()
        strandedFoundation.foundations[0] = [strandedFoundation.stock.removeLast()]
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: strandedFoundation))

        // The single visible waste card must track the waste.
        var badWasteCount = GameState.newPyramidGame()
        var drawn = badWasteCount.stock.removeLast()
        drawn.isFaceUp = true
        badWasteCount.waste = [drawn]
        badWasteCount.wasteDrawCount = 0
        XCTAssertFalse(PyramidPersistenceRules.hasValidLayout(state: badWasteCount))
    }

    func testSanitizationRejectsCorruptPyramidStates() {
        // A duplicated card violates the 52-unique-card invariant.
        var duplicated = GameState.newPyramidGame()
        duplicated.pyramid[0] = duplicated.pyramid[1]
        XCTAssertNil(payload(for: duplicated).sanitizedForRestore(at: DateFixtures.reference))

        // A missing card violates the 52-card count.
        var missing = GameState.newPyramidGame()
        missing.stock.removeLast()
        XCTAssertNil(payload(for: missing).sanitizedForRestore(at: DateFixtures.reference))
    }

    func testOtherVariantsRejectStrandedPyramidCards() {
        var klondike = GameStateFixtures.validPersistenceState()
        let strayCard = klondike.stock.removeLast()
        klondike.pyramid = [strayCard]
        XCTAssertNil(payload(for: klondike, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference))

        var withDiscard = GameStateFixtures.validPersistenceState()
        let discarded = withDiscard.stock.removeLast()
        withDiscard.discard = [discarded]
        XCTAssertNil(payload(for: withDiscard, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference))

        var withRecycles = GameStateFixtures.validPersistenceState()
        withRecycles.wasteRecyclesUsed = 1
        XCTAssertNil(payload(for: withRecycles, stockDrawCount: DrawMode.three.rawValue)
            .sanitizedForRestore(at: DateFixtures.reference))
    }

    func testSanitizationForcesPyramidDrawCounts() throws {
        let state = GameState.newPyramidGame()
        let restored = try XCTUnwrap(
            payload(for: state, stockDrawCount: DrawMode.three.rawValue)
                .sanitizedForRestore(at: DateFixtures.reference)
        )
        XCTAssertEqual(restored.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(restored.scoringDrawCount, DrawMode.three.rawValue)
    }

    func testStatisticsStoreKeepsPyramidIsolated() {
        let defaults = UserDefaults(suiteName: "PyramidPersistenceTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: "PyramidPersistenceTests") }

        GameStatisticsStore.update(for: .pyramid, userDefaults: defaults) { stats in
            stats.recordCompletedGame(
                didWin: true,
                elapsedSeconds: 120,
                finalScore: 250,
                drawCount: 0,
                hintsUsedInGame: 0,
                undosUsedInGame: 0,
                usedRedealInGame: false
            )
        }

        let pyramidStats = GameStatisticsStore.load(for: .pyramid, userDefaults: defaults)
        XCTAssertEqual(pyramidStats.gamesWon, 1)
        // Pyramid has no draw mode, so wins land in the variant-neutral high score.
        XCTAssertEqual(pyramidStats.highScore, 250)
        XCTAssertNil(pyramidStats.highScoreDrawOne)
        XCTAssertNil(pyramidStats.highScoreDrawThree)

        let klondikeStats = GameStatisticsStore.load(for: .klondike, userDefaults: defaults)
        XCTAssertEqual(klondikeStats.gamesPlayed, 0)
    }
}
