import SwiftData
import XCTest
@testable import Computer_Solitaire

@MainActor
final class GamePersistenceStoreTests: XCTestCase {
    func testLoadReturnsNilWhenNoSavedRecord() throws {
        let context = try makeInMemoryContext()
        XCTAssertNil(GamePersistence.load(from: context))
    }

    func testSaveThenLoadRoundTrip() throws {
        let context = try makeInMemoryContext()
        let state = GameStateFixtures.validPersistenceState()
        let payload = SavedGamePayload(
            savedAt: DateFixtures.reference,
            state: state,
            movesCount: 12,
            score: 345,
            gameStartedAt: DateFixtures.plus(-120),
            pauseStartedAt: nil,
            hasAppliedTimeBonus: false,
            finalElapsedSeconds: nil,
            stockDrawCount: DrawMode.three.rawValue,
            scoringDrawCount: DrawMode.three.rawValue,
            history: [],
            redealState: state,
            hasStartedTrackedGame: true,
            isCurrentGameFinalized: false,
            hintRequestsInCurrentGame: 1,
            undosUsedInCurrentGame: 2,
            usedRedealInCurrentGame: false
        )

        try GamePersistence.save(payload, in: context)
        let loaded = GamePersistence.load(from: context)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.movesCount, 12)
        XCTAssertEqual(loaded?.score, 345)
        XCTAssertEqual(loaded?.state, state)
    }

    func testSaveOverwritesExistingRecord() throws {
        let context = try makeInMemoryContext()
        let state = GameStateFixtures.validPersistenceState()
        let first = SavedGamePayload(state: state, movesCount: 1, score: 10, stockDrawCount: DrawMode.three.rawValue, history: [])
        let second = SavedGamePayload(state: state, movesCount: 9, score: 90, stockDrawCount: DrawMode.one.rawValue, history: [])

        try GamePersistence.save(first, in: context)
        try GamePersistence.save(second, in: context)

        let loaded = GamePersistence.load(from: context)
        XCTAssertEqual(loaded?.movesCount, 9)
        XCTAssertEqual(loaded?.score, 90)
        XCTAssertEqual(loaded?.stockDrawCount, DrawMode.one.rawValue)
    }

    func testSaveThrowsForInvalidPayload() throws {
        let context = try makeInMemoryContext()
        let invalid = SavedGamePayload(
            state: GameStateFixtures.emptyBoard(),
            movesCount: 0,
            stockDrawCount: DrawMode.three.rawValue,
            history: []
        )

        XCTAssertThrowsError(try GamePersistence.save(invalid, in: context))
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SavedGameRecord.self, configurations: configuration)
        return ModelContext(container)
    }
}
