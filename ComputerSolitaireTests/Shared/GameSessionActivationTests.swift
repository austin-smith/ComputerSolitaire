import XCTest
@testable import Computer_Solitaire

/// Covers `activateGame(_:restoringFrom:)` — the game-switch path that
/// stashes and resumes per-mode sessions without touching statistics.
@MainActor
final class GameSessionActivationTests: XCTestCase {
    private static var retainedViewModels: [SolitaireViewModel] = []

    // Verifies switching variants mid-game records no loss in either variant's bucket.
    func testActivateVariantDoesNotRecordLoss() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            viewModel.newGame(mode: .klondikeDrawThree)

            viewModel.activateGame(.freecell, restoringFrom: nil)
            viewModel.activateGame(.klondikeDrawThree, restoringFrom: nil)

            XCTAssertEqual(GameStatisticsStore.load(for: .klondikeDrawThree).gamesPlayed, 0)
            XCTAssertEqual(GameStatisticsStore.load(for: .freecell).gamesPlayed, 0)
        }
    }

    // Verifies a stashed session survives the switch round trip exactly: board, progress,
    // score, undo history, and redeal baseline.
    func testActivateVariantRoundTripsStashedSession() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let state = GameStateFixtures.seededFreeCellDeal(seed: 7)
            let redealState = GameStateFixtures.seededFreeCellDeal(seed: 8)
            let snapshot = GameSnapshot(
                state: GameStateFixtures.seededFreeCellDeal(seed: 9),
                movesCount: 11,
                score: 40,
                undoContext: nil
            )
            let payload = makePayload(
                state: state,
                movesCount: 12,
                score: 45,
                history: [snapshot],
                redealState: redealState
            )

            XCTAssertTrue(viewModel.activateGame(.freecell, restoringFrom: payload))

            XCTAssertEqual(viewModel.state, state)
            XCTAssertEqual(viewModel.movesCount, 12)
            XCTAssertEqual(viewModel.score, 45)
            XCTAssertTrue(viewModel.canUndo)

            let stashed = viewModel.persistencePayload()
            XCTAssertEqual(stashed.state, state)
            XCTAssertEqual(stashed.history.count, 1)
            XCTAssertEqual(stashed.history.first?.state, snapshot.state)
            XCTAssertEqual(stashed.redealState, redealState)
        }
    }

    // Verifies a missing payload deals a fresh game for the requested variant.
    func testActivateVariantDealsFreshWhenPayloadNil() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            viewModel.newGame(mode: .klondikeDrawThree)

            XCTAssertFalse(viewModel.activateGame(.freecell, restoringFrom: nil))

            XCTAssertEqual(viewModel.gameVariant, .freecell)
            XCTAssertEqual(viewModel.movesCount, 0)
            XCTAssertEqual(viewModel.score, 0)
            XCTAssertFalse(viewModel.canUndo)
            XCTAssertTrue(viewModel.persistencePayload().hasStartedTrackedGame)
        }
    }

    // Verifies a payload that fails restore sanitization falls back to a fresh deal.
    func testActivateVariantDealsFreshWhenPayloadInvalid() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let invalid = makePayload(state: GameStateFixtures.emptyBoard(), movesCount: 3)

            XCTAssertFalse(viewModel.activateGame(.klondikeDrawThree, restoringFrom: invalid))

            XCTAssertEqual(viewModel.gameVariant, .klondike)
            XCTAssertEqual(viewModel.movesCount, 0)
        }
    }

    // Verifies a payload belonging to another variant is rejected in favor of a fresh deal.
    func testActivateVariantRejectsWrongVariantPayload() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let freeCellPayload = makePayload(
                state: GameStateFixtures.seededFreeCellDeal(seed: 7),
                movesCount: 12
            )

            XCTAssertFalse(viewModel.activateGame(.yukon, restoringFrom: freeCellPayload))

            XCTAssertEqual(viewModel.gameVariant, .yukon)
            XCTAssertEqual(viewModel.movesCount, 0)
        }
    }

    // A legacy save can carry a scoring basis that differs from its mode
    // (pre-per-mode Klondike allowed mid-game draw switches with scoring
    // locked to the deal). Its statistics must land entirely in the bucket
    // of the mode it lives and displays as.
    func testLegacyMismatchedDrawCountsRecordIntoTheModesOwnBucket() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let payload = makePayload(
                state: GameStateFixtures.seededKlondikeDeal(seed: 7),
                movesCount: 12,
                stockDrawCount: DrawMode.one.rawValue,
                scoringDrawCount: DrawMode.three.rawValue
            )

            XCTAssertTrue(viewModel.activateGame(.klondikeDrawOne, restoringFrom: payload))
            viewModel.finalizeCurrentGameIfNeeded(didWin: true, endedAt: DateFixtures.reference)

            let drawOne = GameStatisticsStore.load(for: .klondikeDrawOne)
            XCTAssertEqual(drawOne.gamesPlayed, 1)
            XCTAssertNotNil(drawOne.highScoreDrawOne)
            XCTAssertNil(drawOne.highScoreDrawThree)
            XCTAssertEqual(GameStatisticsStore.load(for: .klondikeDrawThree).gamesPlayed, 0)
        }
    }

    // Verifies a payload belonging to a sibling mode of the same variant is
    // rejected: a draw-three Klondike session must not restore into a
    // requested draw-one game.
    func testActivateGameRejectsWrongModePayloadOfSameVariant() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let drawThreePayload = makePayload(
                state: GameStateFixtures.seededKlondikeDeal(seed: 7),
                movesCount: 12
            )

            XCTAssertFalse(viewModel.activateGame(.klondikeDrawOne, restoringFrom: drawThreePayload))

            XCTAssertEqual(viewModel.gameMode, .klondikeDrawOne)
            XCTAssertEqual(viewModel.movesCount, 0)
        }
    }

    // Verifies elapsed time does not accrue while a session sits stashed: 600s of play
    // stashed for 300s still reports 600s after reactivation.
    func testStashedTimeDoesNotAccrue() {
        withIsolatedStatsStore {
            let clock = TestDateProvider(now: DateFixtures.reference)
            let viewModel = SolitaireViewModel(dateProvider: clock)
            Self.retainedViewModels.append(viewModel)
            let payload = makePayload(
                state: GameStateFixtures.seededFreeCellDeal(seed: 7),
                movesCount: 12,
                savedAt: DateFixtures.plus(-300),
                gameStartedAt: DateFixtures.plus(-900)
            )

            XCTAssertTrue(viewModel.activateGame(.freecell, restoringFrom: payload))

            XCTAssertEqual(viewModel.elapsedActiveSeconds(at: clock.now), 600)
        }
    }

    // A payload stashed while paused restores paused; resuming must not
    // charge the game for time spent paused or stashed.
    func testRestoredPausedPayloadResumesWithoutAccruingStashTime() {
        withIsolatedStatsStore {
            let clock = TestDateProvider(now: DateFixtures.reference)
            let viewModel = SolitaireViewModel(dateProvider: clock)
            Self.retainedViewModels.append(viewModel)
            let payload = makePayload(
                state: GameStateFixtures.seededFreeCellDeal(seed: 7),
                movesCount: 12,
                savedAt: DateFixtures.plus(-300),
                gameStartedAt: DateFixtures.plus(-900),
                pauseStartedAt: DateFixtures.plus(-400)
            )

            XCTAssertTrue(viewModel.activateGame(.freecell, restoringFrom: payload))

            // Still frozen at the pause point: 900 - 400 = 500 active seconds.
            XCTAssertEqual(viewModel.elapsedActiveSeconds(at: clock.now), 500)

            XCTAssertTrue(viewModel.resumeTimeScoring(at: clock.now))
            XCTAssertEqual(viewModel.elapsedActiveSeconds(at: clock.now), 500)

            // The clock only advances again once play resumes.
            clock.now = clock.now.addingTimeInterval(60)
            XCTAssertEqual(viewModel.elapsedActiveSeconds(at: clock.now), 560)
        }
    }

    // Verifies reactivating a finalized (won) session does not finalize it again on New Game.
    func testActivateVariantWithFinalizedPayloadDoesNotRefinalizeOnNewGame() {
        withIsolatedStatsStore {
            let viewModel = makeViewModel()
            let payload = makePayload(
                state: GameStateFixtures.seededFreeCellDeal(seed: 7),
                movesCount: 12,
                isCurrentGameFinalized: true
            )

            XCTAssertTrue(viewModel.activateGame(.freecell, restoringFrom: payload))
            viewModel.newGame()

            XCTAssertEqual(GameStatisticsStore.load(for: .freecell).gamesPlayed, 0)
        }
    }

    // MARK: - Helpers

    private func withIsolatedStatsStore(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let statsKeys = GameMode.allCases.map { GameStatisticsStore.defaultsKey(for: $0) }
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
        state: GameState,
        movesCount: Int,
        score: Int = 0,
        savedAt: Date = DateFixtures.plus(-300),
        gameStartedAt: Date = DateFixtures.plus(-600),
        pauseStartedAt: Date? = nil,
        stockDrawCount: Int = DrawMode.three.rawValue,
        scoringDrawCount: Int = DrawMode.three.rawValue,
        history: [GameSnapshot] = [],
        redealState: GameState? = nil,
        isCurrentGameFinalized: Bool = false
    ) -> SavedGamePayload {
        SavedGamePayload(
            savedAt: savedAt,
            state: state,
            movesCount: movesCount,
            score: score,
            gameStartedAt: gameStartedAt,
            pauseStartedAt: pauseStartedAt,
            hasAppliedTimeBonus: false,
            finalElapsedSeconds: nil,
            stockDrawCount: stockDrawCount,
            scoringDrawCount: scoringDrawCount,
            history: history,
            redealState: redealState ?? state,
            hasStartedTrackedGame: true,
            isCurrentGameFinalized: isCurrentGameFinalized,
            hintRequestsInCurrentGame: 0,
            undosUsedInCurrentGame: 0,
            usedRedealInCurrentGame: false
        )
    }
}
