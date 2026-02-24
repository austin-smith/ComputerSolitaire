import XCTest
@testable import Computer_Solitaire

@MainActor
final class GameSessionTrackingTests: XCTestCase {
    private static var retainedViewModels: [SolitaireViewModel] = []

    // Verifies app startup initializes tracking metadata without starting a trackable game.
    func testInitMarksTrackingStartWithoutActiveTrackedGame() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()

            let stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertNotNil(stats.trackedSince)
            XCTAssertEqual(stats.gamesPlayed, 0)

            let initialProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: initialProbeDate), 0)
        }
    }

    // Verifies the first explicit New Game starts tracking and does not finalize bootstrap state.
    func testFirstNewGameStartsTrackingWithoutFinalizingBootstrapSession() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()

            viewModel.newGame(drawMode: .three)

            let stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 0)

            let trackedProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: trackedProbeDate), 0)
        }
    }

    // Verifies starting a second game finalizes exactly one previously tracked session.
    func testSecondNewGameFinalizesExactlyOneTrackedGame() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()

            viewModel.newGame(drawMode: .three)
            viewModel.newGame(drawMode: .three)

            let stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 1)
        }
    }

    // Verifies redeal finalizes the current tracked session once and starts a fresh one.
    func testRedealFinalizesCurrentTrackedGameExactlyOnce() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()

            viewModel.newGame(drawMode: .three)
            viewModel.redeal()

            let stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 1)

            let trackedProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: trackedProbeDate), 0)
        }
    }

    // Verifies restore resumes live elapsed reporting when payload is active and unfinalized.
    func testRestoreWithActiveTrackedGameReportsLiveElapsed() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
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
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let payload = makePayload(
                hasStartedTrackedGame: true,
                isCurrentGameFinalized: true
            )

            XCTAssertTrue(viewModel.restore(from: payload))
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: .now), 0)

            viewModel.newGame(drawMode: .three)

            let stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 0)
        }
    }

    // Verifies untracked restored sessions stay untracked until an explicit New Game starts tracking.
    func testRestoreWithUntrackedPayloadRemainsUntrackedUntilNewGameStarts() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let payload = makePayload(
                hasStartedTrackedGame: false,
                isCurrentGameFinalized: true
            )

            XCTAssertTrue(viewModel.restore(from: payload))
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: .now), 0)

            viewModel.newGame(drawMode: .three)

            let stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 0)

            let trackedProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: trackedProbeDate), 0)
        }
    }

    // Verifies resetting statistics untracks the active session so pre-reset progress is not counted.
    func testResetStatisticsUntracksCurrentSessionUntilNextNewGame() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()

            viewModel.newGame(drawMode: .three)
            let activeProbeDate = viewModel.gameStartedAt.addingTimeInterval(120)
            XCTAssertGreaterThan(viewModel.unfinalizedElapsedSecondsForStats(at: activeProbeDate), 0)

            GameStatisticsStore.reset(for: .klondike)
            viewModel.resetStatisticsTracking()
            XCTAssertEqual(viewModel.unfinalizedElapsedSecondsForStats(at: activeProbeDate), 0)
            let resetPayload = viewModel.persistencePayload()
            XCTAssertFalse(resetPayload.hasStartedTrackedGame)
            XCTAssertTrue(resetPayload.isCurrentGameFinalized)

            viewModel.newGame(drawMode: .three)
            var stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 0)

            viewModel.newGame(drawMode: .three)
            stats = GameStatisticsStore.load(for: .klondike)
            XCTAssertEqual(stats.gamesPlayed, 1)
        }
    }

    // Verifies switching variants finalizes the prior variant into its own stats bucket.
    func testVariantSwitchFinalizesIntoPriorVariantBucket() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()

            viewModel.newGame(variant: .klondike, drawMode: .three)
            viewModel.newGame(variant: .freecell, drawMode: .three)

            var klondikeStats = GameStatisticsStore.load(for: .klondike)
            var freeCellStats = GameStatisticsStore.load(for: .freecell)
            XCTAssertEqual(klondikeStats.gamesPlayed, 1)
            XCTAssertEqual(freeCellStats.gamesPlayed, 0)

            viewModel.newGame(variant: .klondike, drawMode: .three)

            klondikeStats = GameStatisticsStore.load(for: .klondike)
            freeCellStats = GameStatisticsStore.load(for: .freecell)
            XCTAssertEqual(klondikeStats.gamesPlayed, 1)
            XCTAssertEqual(freeCellStats.gamesPlayed, 1)
        }
    }

    private func withIsolatedStatsStore(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let statsKeys = GameVariant.allCases.map { GameStatisticsStore.defaultsKey(for: $0) }
        let previousStatsData = statsKeys.reduce(into: [String: Data]()) { result, key in
            if let data = defaults.data(forKey: key) {
                result[key] = data
            }
        }
        for key in statsKeys {
            defaults.removeObject(forKey: key)
        }
        defer {
            for key in statsKeys {
                if let value = previousStatsData[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        body()
    }

    private func makeViewModel() -> SolitaireViewModel {
        let viewModel = SolitaireViewModel()
        Self.retainedViewModels.append(viewModel)
        return viewModel
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
