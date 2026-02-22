import XCTest
@testable import Computer_Solitaire

@MainActor
final class GameStatisticsCleanWinTests: XCTestCase {
    func testCleanWinIncrementsWhenNoHintUndoOrRedealWasUsed() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 120,
            finalScore: 200,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.gamesPlayed, 1)
        XCTAssertEqual(stats.gamesWon, 1)
        XCTAssertEqual(stats.cleanWins, 1)
        XCTAssertEqual(stats.cleanWinRate, 1.0, accuracy: 0.0001)
    }

    func testWinWithHintIsNotCleanWin() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 180,
            finalScore: 250,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 1,
            undosUsedInGame: 0,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.gamesWon, 1)
        XCTAssertEqual(stats.cleanWins, 0)
    }

    func testWinWithUndoIsNotCleanWin() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 180,
            finalScore: 250,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 0,
            undosUsedInGame: 2,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.gamesWon, 1)
        XCTAssertEqual(stats.cleanWins, 0)
    }

    func testWinWithRedealIsNotCleanWin() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: true,
            elapsedSeconds: 180,
            finalScore: 250,
            drawCount: DrawMode.three.rawValue,
            hintsUsedInGame: 0,
            undosUsedInGame: 0,
            usedRedealInGame: true
        )

        XCTAssertEqual(stats.gamesWon, 1)
        XCTAssertEqual(stats.cleanWins, 0)
    }

    func testLossNeverCountsAsCleanWin() {
        var stats = GameStatistics()

        stats.recordCompletedGame(
            didWin: false,
            elapsedSeconds: 300,
            finalScore: 150,
            drawCount: DrawMode.one.rawValue,
            hintsUsedInGame: 2,
            undosUsedInGame: 3,
            usedRedealInGame: false
        )

        XCTAssertEqual(stats.gamesPlayed, 1)
        XCTAssertEqual(stats.gamesWon, 0)
        XCTAssertEqual(stats.cleanWins, 0)
    }

    func testDecodingLegacyStatsDefaultsCleanWinsToZero() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "gamesPlayed": 8,
          "gamesWon": 3,
          "totalTimeSeconds": 1200,
          "bestTimeSeconds": 140,
          "highScoreDrawThree": 780,
          "highScoreDrawOne": 620
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(GameStatistics.self, from: data)

        XCTAssertEqual(decoded.cleanWins, 0)
        XCTAssertEqual(decoded.gamesPlayed, 8)
        XCTAssertEqual(decoded.gamesWon, 3)
    }
}
