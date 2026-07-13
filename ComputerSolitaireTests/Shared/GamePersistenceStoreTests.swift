import SwiftData
import XCTest
@testable import Computer_Solitaire

@MainActor
final class GamePersistenceStoreTests: XCTestCase {
    func testLoadReturnsNilForVariantWithoutSave() throws {
        let context = try makeInMemoryContext()
        XCTAssertNil(GamePersistence.load(mode: .klondikeDrawThree, from: context))
        XCTAssertNil(GamePersistence.load(mode: .freecell, from: context))
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
        let loaded = GamePersistence.load(mode: .klondikeDrawThree, from: context)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.movesCount, 12)
        XCTAssertEqual(loaded?.score, 345)
        XCTAssertEqual(loaded?.state, state)
    }

    // A statistics reset must reach stashed sessions: their games stay
    // playable but can no longer finalize pre-reset play into fresh buckets.
    func testInvalidateStatisticsTrackingRewritesStashedSlots() throws {
        let context = try makeInMemoryContext()
        let state = GameStateFixtures.validPersistenceState()
        let payload = SavedGamePayload(
            state: state,
            movesCount: 12,
            stockDrawCount: DrawMode.three.rawValue,
            history: [],
            hasStartedTrackedGame: true,
            isCurrentGameFinalized: false,
            hintRequestsInCurrentGame: 3,
            undosUsedInCurrentGame: 2
        )
        try GamePersistence.save(payload, in: context)

        GamePersistence.invalidateStatisticsTracking(for: [.klondikeDrawThree], in: context)

        let invalidated = try XCTUnwrap(GamePersistence.load(mode: .klondikeDrawThree, from: context))
        XCTAssertFalse(invalidated.hasStartedTrackedGame)
        XCTAssertEqual(invalidated.hintRequestsInCurrentGame, 0)
        XCTAssertEqual(invalidated.undosUsedInCurrentGame, 0)
        // The game itself is untouched — only its tracking is reset.
        XCTAssertEqual(invalidated.movesCount, 12)
        XCTAssertEqual(invalidated.state, state)

        // Slots without a save are skipped without disturbing anything.
        GamePersistence.invalidateStatisticsTracking(for: [.freecell], in: context)
        XCTAssertNil(GamePersistence.load(mode: .freecell, from: context))
    }

    func testSaveKeysRecordByPayloadVariant() throws {
        let context = try makeInMemoryContext()
        let klondikeState = GameStateFixtures.validPersistenceState()
        let freeCellState = GameStateFixtures.seededFreeCellDeal(seed: 7)

        try GamePersistence.save(makePayload(state: klondikeState, movesCount: 3), in: context)
        try GamePersistence.save(makePayload(state: freeCellState, movesCount: 8), in: context)

        let klondike = GamePersistence.load(mode: .klondikeDrawThree, from: context)
        let freecell = GamePersistence.load(mode: .freecell, from: context)

        XCTAssertEqual(klondike?.state, klondikeState)
        XCTAssertEqual(klondike?.movesCount, 3)
        XCTAssertEqual(freecell?.state, freeCellState)
        XCTAssertEqual(freecell?.movesCount, 8)
        XCTAssertNil(GamePersistence.load(mode: .yukon, from: context))
    }

    func testSaveOverwritesOnlySameVariantSlot() throws {
        let context = try makeInMemoryContext()
        let freeCellState = GameStateFixtures.seededFreeCellDeal(seed: 7)

        try GamePersistence.save(makePayload(state: freeCellState, movesCount: 8), in: context)
        try GamePersistence.save(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 1),
            in: context
        )
        try GamePersistence.save(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 9),
            in: context
        )

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 9)
        XCTAssertEqual(GamePersistence.load(mode: .freecell, from: context)?.movesCount, 8)
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

    func testKlondikeDrawModesKeepIndependentSlots() throws {
        let context = try makeInMemoryContext()
        let drawThreeState = GameStateFixtures.validPersistenceState()
        let drawOneState = GameStateFixtures.validPersistenceState()

        try GamePersistence.save(
            SavedGamePayload(
                state: drawThreeState,
                movesCount: 3,
                stockDrawCount: DrawMode.three.rawValue,
                history: []
            ),
            in: context
        )
        try GamePersistence.save(
            SavedGamePayload(
                state: drawOneState,
                movesCount: 7,
                stockDrawCount: DrawMode.one.rawValue,
                history: []
            ),
            in: context
        )

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 3)
        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawOne, from: context)?.movesCount, 7)
    }

    // MARK: - Legacy record migration

    func testMigrationSplitsVariantKeyedKlondikeRecordByDrawCount() throws {
        let context = try makeInMemoryContext()
        let payload = makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 5)
        context.insert(SavedGameRecord(
            key: "klondike",
            snapshotData: try JSONEncoder().encode(payload)
        ))
        try context.save()

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 5)
        XCTAssertNil(GamePersistence.load(mode: .klondikeDrawOne, from: context))
        XCTAssertNil(try fetchRecord(forKey: "klondike", in: context))
    }


    func testMigrationRekeysLegacyRecordToPayloadVariant() throws {
        let context = try makeInMemoryContext()
        let state = GameStateFixtures.seededFreeCellDeal(seed: 7)
        try insertLegacyRecord(makePayload(state: state, movesCount: 5), in: context)

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        let loaded = GamePersistence.load(mode: .freecell, from: context)
        XCTAssertEqual(loaded?.state, state)
        XCTAssertEqual(loaded?.movesCount, 5)
        XCTAssertNil(try fetchRecord(forKey: SavedGameRecord.legacyRecordKey, in: context))
    }

    // The game migrated out of the single legacy slot was on screen when the
    // old build last ran; migration reports its mode so first hydration can
    // open it even when stored settings lag the payload.
    func testMigrationReportsModeOfLegacyCurrentGame() throws {
        let context = try makeInMemoryContext()
        let state = GameStateFixtures.seededFreeCellDeal(seed: 7)
        try insertLegacyRecord(makePayload(state: state, movesCount: 5), in: context)

        let migratedMode = GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertEqual(migratedMode, .freecell)

        // Later launches have no legacy slot and report nothing.
        XCTAssertNil(GamePersistence.migrateLegacyRecordsIfNeeded(in: context))
    }

    func testMigrationIsIdempotent() throws {
        let context = try makeInMemoryContext()
        try insertLegacyRecord(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 5),
            in: context
        )

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)
        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 5)
        XCTAssertEqual(try fetchAllRecords(in: context).count, 1)
    }

    func testMigrationNoOpWithoutLegacyRecord() throws {
        let context = try makeInMemoryContext()
        try GamePersistence.save(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 5),
            in: context
        )

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 5)
        XCTAssertEqual(try fetchAllRecords(in: context).count, 1)
    }

    func testMigrationDeletesUndecodableLegacyRecord() throws {
        let context = try makeInMemoryContext()
        context.insert(SavedGameRecord(
            key: SavedGameRecord.legacyRecordKey,
            snapshotData: Data("not a payload".utf8)
        ))
        try context.save()

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertTrue(try fetchAllRecords(in: context).isEmpty)
    }

    func testMigrationKeepsOccupyingRecordWhenNewerThanLegacy() throws {
        let context = try makeInMemoryContext()
        try insertLegacyRecord(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 5),
            in: context,
            updatedAt: DateFixtures.plus(-60)
        )
        try GamePersistence.save(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 9),
            in: context,
            now: DateFixtures.reference
        )

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 9)
        XCTAssertNil(try fetchRecord(forKey: SavedGameRecord.legacyRecordKey, in: context))
        XCTAssertEqual(try fetchAllRecords(in: context).count, 1)
    }

    func testMigrationRekeysLegacyRecordWhenNewerThanOccupying() throws {
        let context = try makeInMemoryContext()
        try GamePersistence.save(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 9),
            in: context,
            now: DateFixtures.plus(-60)
        )
        try insertLegacyRecord(
            makePayload(state: GameStateFixtures.validPersistenceState(), movesCount: 5),
            in: context,
            updatedAt: DateFixtures.reference
        )

        GamePersistence.migrateLegacyRecordsIfNeeded(in: context)

        XCTAssertEqual(GamePersistence.load(mode: .klondikeDrawThree, from: context)?.movesCount, 5)
        XCTAssertNil(try fetchRecord(forKey: SavedGameRecord.legacyRecordKey, in: context))
        XCTAssertEqual(try fetchAllRecords(in: context).count, 1)
    }

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SavedGameRecord.self, configurations: configuration)
        return ModelContext(container)
    }

    private func makePayload(state: GameState, movesCount: Int) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: movesCount,
            stockDrawCount: DrawMode.three.rawValue,
            history: []
        )
    }

    private func insertLegacyRecord(
        _ payload: SavedGamePayload,
        in context: ModelContext,
        updatedAt: Date = DateFixtures.reference
    ) throws {
        context.insert(SavedGameRecord(
            key: SavedGameRecord.legacyRecordKey,
            snapshotData: try JSONEncoder().encode(payload),
            updatedAt: updatedAt
        ))
        try context.save()
    }

    private func fetchRecord(forKey key: String, in context: ModelContext) throws -> SavedGameRecord? {
        var descriptor = FetchDescriptor<SavedGameRecord>(
            predicate: #Predicate<SavedGameRecord> { record in
                record.key == key
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchAllRecords(in context: ModelContext) throws -> [SavedGameRecord] {
        try context.fetch(FetchDescriptor<SavedGameRecord>())
    }
}
