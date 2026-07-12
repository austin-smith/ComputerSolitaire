import XCTest
@testable import Computer_Solitaire

@MainActor
final class GameStatisticsStoreTests: XCTestCase {
    func testRecordCompletedGameUpdatesBestTimeAndHighScoreByDrawMode() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 200,
            finalScore: 300,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )
        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 150,
            finalScore: 250,
            drawCount: DrawMode.one.rawValue,
            hintsUsedInGame: 1,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.gamesPlayed, 2)
        XCTAssertEqual(stats.gamesWon, 2)
        XCTAssertEqual(stats.bestTimeSeconds, 150)
        XCTAssertEqual(stats.highScoreDrawThree, 300)
        XCTAssertEqual(stats.highScoreDrawOne, 250)
        XCTAssertEqual(stats.cleanWins, 1)
    }

    func testRecordCompletedGameWithoutDrawModeUpdatesVariantNeutralHighScore() {
        // FreeCell and Yukon have no stock, so they report draw count 0: their wins
        // must land in the single variant-neutral high score, never in Klondike's
        // per-draw-mode fields.
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 180,
            finalScore: 420,
            drawCount: 0,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )
        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 240,
            finalScore: 350,
            drawCount: 0,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.highScore, 420)
        XCTAssertNil(stats.highScoreDrawThree)
        XCTAssertNil(stats.highScoreDrawOne)
    }

    func testKlondikeDrawModeWinsDoNotTouchVariantNeutralHighScore() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 100,
            finalScore: 500,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.highScoreDrawThree, 500)
        XCTAssertNil(stats.highScore)
    }

    func testStatisticsDecodingToleratesPayloadWithoutHighScoreField() throws {
        // Statistics saved before the variant-neutral high score existed must load
        // with the field simply absent.
        let legacyJSON = """
        {"schemaVersion": 1, "gamesPlayed": 3, "gamesWon": 2, "totalTimeSeconds": 600, "cleanWins": 1}
        """
        let stats = try JSONDecoder().decode(
            GameStatistics.self,
            from: try XCTUnwrap(legacyJSON.data(using: .utf8))
        )

        XCTAssertNil(stats.highScore)
        XCTAssertEqual(stats.gamesPlayed, 3)
        XCTAssertEqual(stats.gamesWon, 2)
    }

    func testRecordCompletedGameUsesOverflowSafeCounters() {
        var stats = GameStatistics(
            gamesPlayed: Int.max,
            gamesWon: Int.max,
            totalTimeSeconds: Int.max,
            cleanWins: Int.max
        )

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: Int.max,
            finalScore: 100,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.gamesPlayed, Int.max)
        XCTAssertEqual(stats.gamesWon, Int.max)
        XCTAssertEqual(stats.totalTimeSeconds, Int.max)
        XCTAssertEqual(stats.cleanWins, Int.max)
    }

    func testStatisticsStoreMarkTrackingStartedAndReset() throws {
        let defaults = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        GameStatisticsStore.markTrackingStarted(
            for: .klondike,
            userDefaults: defaults,
            at: DateFixtures.reference
        )
        let marked = GameStatisticsStore.load(for: .klondike, userDefaults: defaults)
        XCTAssertEqual(marked.trackedSince, DateFixtures.reference)

        GameStatisticsStore.markTrackingStarted(
            for: .klondike,
            userDefaults: defaults,
            at: DateFixtures.plus(60)
        )
        let notOverwritten = GameStatisticsStore.load(for: .klondike, userDefaults: defaults)
        XCTAssertEqual(notOverwritten.trackedSince, DateFixtures.reference)

        GameStatisticsStore.reset(
            for: .klondike,
            userDefaults: defaults,
            at: DateFixtures.plus(120)
        )
        let reset = GameStatisticsStore.load(for: .klondike, userDefaults: defaults)
        XCTAssertEqual(reset.trackedSince, DateFixtures.plus(120))
        XCTAssertEqual(reset.gamesPlayed, 0)
        XCTAssertEqual(reset.gamesWon, 0)
    }

    func testStatisticsStoreUpdatePersistsMutation() throws {
        let defaults = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        GameStatisticsStore.update(for: .klondike, userDefaults: defaults) { stats in
            stats.recordCompletedGame(
                didWin: true,
                elapsedSeconds: 123,
                finalScore: 456,
                drawCount: DrawMode.three.rawValue,
                hintsUsedInGame: 0,
                undosUsedInGame: 0,
                usedRedealInGame: false
            )
        }

        let loaded = GameStatisticsStore.load(for: .klondike, userDefaults: defaults)
        XCTAssertEqual(loaded.gamesPlayed, 1)
        XCTAssertEqual(loaded.gamesWon, 1)
        XCTAssertEqual(loaded.bestTimeSeconds, 123)
    }

    func testVariantStoresRemainIsolated() throws {
        let defaults = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        GameStatisticsStore.update(for: .klondike, userDefaults: defaults) { stats in
            stats.recordCompletedGame(
                didWin: true,
                elapsedSeconds: 100,
                finalScore: 200,
                drawCount: DrawMode.three.rawValue,
                hintsUsedInGame: 0,
                undosUsedInGame: 0,
                usedRedealInGame: false
            )
        }

        let klondikeStats = GameStatisticsStore.load(for: .klondike, userDefaults: defaults)
        let freeCellStats = GameStatisticsStore.load(for: .freecell, userDefaults: defaults)

        XCTAssertEqual(klondikeStats.gamesPlayed, 1)
        XCTAssertEqual(klondikeStats.gamesWon, 1)
        XCTAssertEqual(freeCellStats.gamesPlayed, 0)
        XCTAssertEqual(freeCellStats.gamesWon, 0)
    }

    func testAggregatedStatisticsCombinesCoreMetricsAcrossVariants() {
        let klondikeStats = GameStatistics(
            trackedSince: DateFixtures.plus(300),
            gamesPlayed: 4,
            gamesWon: 3,
            totalTimeSeconds: 800,
            bestTimeSeconds: 120,
            highScoreDrawThree: 500,
            highScoreDrawOne: 300,
            cleanWins: 2
        )
        let freeCellStats = GameStatistics(
            trackedSince: DateFixtures.reference,
            gamesPlayed: 6,
            gamesWon: 4,
            totalTimeSeconds: 1200,
            bestTimeSeconds: 150,
            highScoreDrawThree: nil,
            highScoreDrawOne: nil,
            highScore: 260,
            cleanWins: 3
        )
        let yukonStats = GameStatistics(
            trackedSince: DateFixtures.plus(600),
            gamesPlayed: 2,
            gamesWon: 1,
            totalTimeSeconds: 400,
            bestTimeSeconds: 180,
            highScore: 610,
            cleanWins: 0
        )

        let aggregate = GameStatistics.aggregated([klondikeStats, freeCellStats, yukonStats])

        XCTAssertEqual(aggregate.trackedSince, DateFixtures.reference)
        XCTAssertEqual(aggregate.gamesPlayed, 12)
        XCTAssertEqual(aggregate.gamesWon, 8)
        XCTAssertEqual(aggregate.totalTimeSeconds, 2400)
        XCTAssertEqual(aggregate.bestTimeSeconds, 120)
        XCTAssertEqual(aggregate.cleanWins, 5)
        XCTAssertEqual(aggregate.highScoreDrawThree, 500)
        XCTAssertEqual(aggregate.highScoreDrawOne, 300)
        XCTAssertEqual(aggregate.highScore, 610)
    }

    func testAggregatedStatisticsUsesOverflowSafeCounters() {
        let largeA = GameStatistics(
            gamesPlayed: Int.max,
            gamesWon: Int.max,
            totalTimeSeconds: Int.max,
            cleanWins: Int.max
        )
        let largeB = GameStatistics(
            gamesPlayed: 100,
            gamesWon: 100,
            totalTimeSeconds: 100,
            cleanWins: 100
        )

        let aggregate = GameStatistics.aggregated([largeA, largeB])

        XCTAssertEqual(aggregate.gamesPlayed, Int.max)
        XCTAssertEqual(aggregate.gamesWon, Int.max)
        XCTAssertEqual(aggregate.totalTimeSeconds, Int.max)
        XCTAssertEqual(aggregate.cleanWins, Int.max)
    }

    private let defaultsSuiteName = "ComputerSolitaire.GameStatisticsStoreTests"

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}
