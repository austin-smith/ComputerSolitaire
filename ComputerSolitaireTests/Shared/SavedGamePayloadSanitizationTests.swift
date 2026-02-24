import XCTest
@testable import Computer_Solitaire

@MainActor
final class SavedGamePayloadSanitizationTests: XCTestCase {
    func testSanitizedForRestoreRejectsUnsupportedSchema() {
        let payload = makePayload(schemaVersion: 999, state: GameStateFixtures.validPersistenceState())
        XCTAssertNil(payload.sanitizedForRestore())
    }

    func testSanitizedForRestoreRejectsInvalidStateShape() {
        let payload = makePayload(state: GameStateFixtures.emptyBoard())
        XCTAssertNil(payload.sanitizedForRestore())
    }

    func testSanitizedForRestoreClampsDrawModesCountsAndHistory() {
        let validState = GameStateFixtures.validPersistenceState()
        let validSnapshot = GameSnapshot(
            state: validState,
            movesCount: 2,
            score: -50,
            hasAppliedTimeBonus: false,
            undoContext: nil
        )

        let payload = SavedGamePayload(
            savedAt: Date(),
            state: validState,
            movesCount: -7,
            score: -99,
            gameStartedAt: Date(),
            pauseStartedAt: nil,
            hasAppliedTimeBonus: false,
            finalElapsedSeconds: -40,
            stockDrawCount: 999,
            scoringDrawCount: -1,
            history: [validSnapshot],
            redealState: validState,
            hasStartedTrackedGame: false,
            isCurrentGameFinalized: true,
            hintRequestsInCurrentGame: -3,
            undosUsedInCurrentGame: -5,
            usedRedealInCurrentGame: true
        )

        let sanitized = payload.sanitizedForRestore()
        XCTAssertNotNil(sanitized)
        XCTAssertEqual(sanitized?.stockDrawCount, DrawMode.three.rawValue)
        XCTAssertEqual(sanitized?.scoringDrawCount, DrawMode.three.rawValue)
        XCTAssertEqual(sanitized?.movesCount, 0)
        XCTAssertEqual(sanitized?.score, 0)
        XCTAssertLessThanOrEqual(sanitized?.state.wasteDrawCount ?? 0, sanitized?.state.waste.count ?? 0)
        XCTAssertEqual(sanitized?.history.count, 1)
        XCTAssertTrue((sanitized?.history.allSatisfy { $0.score >= 0 }) ?? false)
        XCTAssertNotNil(sanitized?.redealState)
        XCTAssertFalse(sanitized?.isCurrentGameFinalized ?? true)
        XCTAssertEqual(sanitized?.hintRequestsInCurrentGame, 0)
        XCTAssertEqual(sanitized?.undosUsedInCurrentGame, 0)
        XCTAssertFalse(sanitized?.usedRedealInCurrentGame ?? true)
    }

    private func makePayload(
        schemaVersion: Int = SavedGamePayload.currentSchemaVersion,
        state: GameState
    ) -> SavedGamePayload {
        SavedGamePayload(
            schemaVersion: schemaVersion,
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
