import XCTest
@testable import Computer_Solitaire

@MainActor
final class GameSessionTrackingTests: XCTestCase {

    // Verifies app startup initializes tracking metadata without starting a trackable game.
    func testInitMarksTrackingStartWithoutActiveTrackedGame() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()

            let stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertNotNil(stats.trackedSince)
            XCTAssertEqual(stats.gamesPlayed, 0)

            let initialProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: initialProbeDate), 0)
        }
    }

    // Verifies the first explicit New Game starts tracking and does not finalize bootstrap state.
    func testFirstNewGameStartsTrackingWithoutFinalizingBootstrapSession() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()

            viewModel.newGame()

            let stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 0)

            let trackedProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: trackedProbeDate), 0)
        }
    }

    // Verifies starting a second game finalizes exactly one previously tracked session.
    func testSecondNewGameFinalizesExactlyOneTrackedGame() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()

            viewModel.newGame()
            viewModel.newGame()

            let stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 1)
        }
    }

    // Verifies redeal finalizes the current tracked session once and starts a fresh one.
    func testRedealFinalizesCurrentTrackedGameExactlyOnce() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()

            viewModel.newGame()
            viewModel.redeal()

            let stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 1)

            let trackedProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: trackedProbeDate), 0)
        }
    }

    // Verifies restore resumes live elapsed reporting when payload is active and unfinalized.
    func testRestoreWithActiveTrackedGameReportsLiveElapsed() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()
            let payload = makePayload(
                hasStartedTrackedGame: true,
                isCurrentGameFinalized: false
            )

            XCTAssertTrue(viewModel.restore(from: payload))
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: .now), 0)
        }
    }

    // Verifies finalized restored sessions are not finalized again when starting a new game.
    func testRestoreWithFinalizedGameDoesNotFinalizeAgainOnNewGame() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()
            let payload = makePayload(
                hasStartedTrackedGame: true,
                isCurrentGameFinalized: true
            )

            XCTAssertTrue(viewModel.restore(from: payload))
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: .now), 0)

            viewModel.newGame()

            let stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 0)
        }
    }

    // Verifies untracked restored sessions stay untracked until an explicit New Game starts tracking.
    func testRestoreWithUntrackedPayloadRemainsUntrackedUntilNewGameStarts() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()
            let payload = makePayload(
                hasStartedTrackedGame: false,
                isCurrentGameFinalized: true
            )

            XCTAssertTrue(viewModel.restore(from: payload))
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: .now), 0)

            viewModel.newGame()

            let stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 0)

            let trackedProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: trackedProbeDate), 0)
        }
    }

    // Verifies resetting statistics untracks the active session so pre-reset progress is not counted.
    func testResetStatisticsUntracksCurrentSessionUntilNextNewGame() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()

            viewModel.newGame()
            let activeProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: activeProbeDate), 0)

            GameStatisticsStore.reset(for: .klondikeDrawThree)
            viewModel.resetStatisticsTracking()
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: activeProbeDate), 0)
            let resetPayload = viewModel.persistencePayload()
            XCTAssertFalse(resetPayload.hasStartedTrackedGame)
            XCTAssertTrue(resetPayload.isCurrentGameFinalized)

            viewModel.newGame()
            var stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 0)

            viewModel.newGame()
            stats = GameStatisticsStore.load(for: .klondikeDrawThree)
            XCTAssertEqual(stats.gamesPlayed, 1)
        }
    }

    // Verifies an explicit New Game in another mode finalizes the prior game into its
    // own stats bucket. (The game picker goes through `activateGame` instead, which
    // never finalizes — see GameSessionActivationTests.)
    func testNewGameAcrossModesFinalizesIntoPriorBucket() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()

            viewModel.newGame(mode: .klondikeDrawThree)
            viewModel.newGame(mode: .freecell)

            var klondikeStats = GameStatisticsStore.load(for: .klondikeDrawThree)
            var freeCellStats = GameStatisticsStore.load(for: .freecell)
            XCTAssertEqual(klondikeStats.gamesPlayed, 1)
            XCTAssertEqual(freeCellStats.gamesPlayed, 0)

            viewModel.newGame(mode: .yukon)

            klondikeStats = GameStatisticsStore.load(for: .klondikeDrawThree)
            freeCellStats = GameStatisticsStore.load(for: .freecell)
            var yukonStats = GameStatisticsStore.load(for: .yukon)
            XCTAssertEqual(klondikeStats.gamesPlayed, 1)
            XCTAssertEqual(freeCellStats.gamesPlayed, 1)
            XCTAssertEqual(yukonStats.gamesPlayed, 0)

            viewModel.newGame(mode: .klondikeDrawThree)

            klondikeStats = GameStatisticsStore.load(for: .klondikeDrawThree)
            yukonStats = GameStatisticsStore.load(for: .yukon)
            XCTAssertEqual(klondikeStats.gamesPlayed, 1)
            XCTAssertEqual(yukonStats.gamesPlayed, 1)
        }
    }


    private func makePayload(
        hasStartedTrackedGame: Bool,
        isCurrentGameFinalized: Bool
    ) -> SavedGamePayload {
        let state = GameState.newGame()
        return SavedGamePayload(
            savedAt: Date().addingTimeInterval(-300),
            state: state,
            movesCount: 0,
            score: 0,
            gameStartedAt: Date().addingTimeInterval(-600),
            pauseStartedAt: nil,
            hasAppliedTimeBonus: false,
            finalElapsedSeconds: nil,
            stockDrawCount: DrawMode.three.rawValue,
            scoringDrawCount: DrawMode.three.rawValue,
            history: [],
            redealState: state,
            hasStartedTrackedGame: hasStartedTrackedGame,
            isCurrentGameFinalized: isCurrentGameFinalized,
            hintRequestsInCurrentGame: 0,
            undosUsedInCurrentGame: 0,
            usedRedealInCurrentGame: false
        )
    }
}
