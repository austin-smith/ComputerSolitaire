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

    func testStatisticsStoreMarkTrackingStartedAndReset() {
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        GameStatisticsStore.markTrackingStarted(userDefaults: defaults, at: DateFixtures.reference)
        let marked = GameStatisticsStore.load(userDefaults: defaults)
        XCTAssertEqual(marked.trackedSince, DateFixtures.reference)

        GameStatisticsStore.markTrackingStarted(userDefaults: defaults, at: DateFixtures.plus(60))
        let notOverwritten = GameStatisticsStore.load(userDefaults: defaults)
        XCTAssertEqual(notOverwritten.trackedSince, DateFixtures.reference)

        GameStatisticsStore.reset(userDefaults: defaults, at: DateFixtures.plus(120))
        let reset = GameStatisticsStore.load(userDefaults: defaults)
        XCTAssertEqual(reset.trackedSince, DateFixtures.plus(120))
        XCTAssertEqual(reset.gamesPlayed, 0)
        XCTAssertEqual(reset.gamesWon, 0)
    }

    func testStatisticsStoreUpdatePersistsMutation() {
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        GameStatisticsStore.update(userDefaults: defaults) { stats in
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

        let loaded = GameStatisticsStore.load(userDefaults: defaults)
        XCTAssertEqual(loaded.gamesPlayed, 1)
        XCTAssertEqual(loaded.gamesWon, 1)
        XCTAssertEqual(loaded.bestTimeSeconds, 123)
    }

    private let defaultsSuiteName = "ComputerSolitaire.GameStatisticsStoreTests"

    private func makeIsolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}
