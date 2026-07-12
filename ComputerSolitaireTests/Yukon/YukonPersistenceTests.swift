import XCTest
@testable import Computer_Solitaire

@MainActor
final class YukonPersistenceTests: XCTestCase {
    func testValidYukonPayloadSurvivesSanitization() {
        let state = GameStateFixtures.seededYukonDeal(seed: 1)
        let payload = makePayload(state: state)

        let sanitized = payload.sanitizedForRestore()
        XCTAssertNotNil(sanitized)
        XCTAssertEqual(sanitized?.state.variant, .yukon)
        XCTAssertEqual(sanitized?.state.wasteDrawCount, 0)
        XCTAssertEqual(sanitized?.stockDrawCount, DrawMode.three.rawValue)
    }

    func testInvalidYukonLayoutsAreRejected() {
        var eightPiles = GameStateFixtures.seededYukonDeal(seed: 2)
        eightPiles.tableau.append([])
        XCTAssertNil(makePayload(state: eightPiles).sanitizedForRestore())

        var nonEmptyStock = GameStateFixtures.seededYukonDeal(seed: 3)
        nonEmptyStock.stock = [nonEmptyStock.tableau[6].removeLast()]
        XCTAssertNil(makePayload(state: nonEmptyStock).sanitizedForRestore())

        // Yukon renders no free-cell slots: a card stranded there would be invisible
        // and the game unwinnable, so the layout gate must reject it.
        var strandedFreeCell = GameStateFixtures.seededYukonDeal(seed: 4)
        strandedFreeCell.freeCells[0] = strandedFreeCell.tableau[6].removeLast()
        XCTAssertNil(makePayload(state: strandedFreeCell).sanitizedForRestore())
    }

    func testViewModelRoundTripPreservesYukonGame() {
        let viewModel = SolitaireViewModel()
        viewModel.newGame(variant: .yukon)
        let payload = viewModel.persistencePayload()

        let restored = SolitaireViewModel()
        XCTAssertTrue(restored.restore(from: payload))
        XCTAssertEqual(restored.state.variant, .yukon)
        XCTAssertEqual(restored.state, viewModel.state)
    }

    private func makePayload(state: GameState) -> SavedGamePayload {
        SavedGamePayload(
            savedAt: DateFixtures.reference,
            state: state,
            movesCount: 0,
            score: 0,
            gameStartedAt: DateFixtures.reference,
            pauseStartedAt: nil,
            hasAppliedTimeBonus: false,
            finalElapsedSeconds: nil,
            stockDrawCount: DrawMode.three.rawValue,
            scoringDrawCount: DrawMode.three.rawValue,
            history: [],
            redealState: state,
            hasStartedTrackedGame: true,
            isCurrentGameFinalized: false,
            hintRequestsInCurrentGame: 0,
            undosUsedInCurrentGame: 0,
            usedRedealInCurrentGame: false
        )
    }
}
