import XCTest
@testable import Computer_Solitaire

@MainActor
final class GolfMatchTests: XCTestCase {
    // MARK: Model

    func testMatchStateInvariants() {
        var match = GolfMatchState()
        XCTAssertEqual(match.currentHoleNumber, 1)
        XCTAssertEqual(match.runningTotal, 0)
        XCTAssertFalse(match.isComplete)

        match.completedHoleScores = [3, -2, 7]
        XCTAssertEqual(match.currentHoleNumber, 4)
        XCTAssertEqual(match.runningTotal, 8, "Negative holes subtract from the total")
        XCTAssertFalse(match.isComplete)

        match.completedHoleScores = Array(repeating: 5, count: GolfMatchState.holeCount)
        XCTAssertEqual(match.currentHoleNumber, GolfMatchState.holeCount)
        XCTAssertEqual(match.runningTotal, GolfMatchState.parTotal)
        XCTAssertTrue(match.isComplete)
    }

    func testLegacyMatchStateDecodesAsTracked() throws {
        // Scorecards persisted before the eligibility flag existed decode as
        // counting toward statistics.
        let legacy = Data(#"{"completedHoleScores":[3,-2]}"#.utf8)
        let decoded = try JSONDecoder().decode(GolfMatchState.self, from: legacy)
        XCTAssertEqual(decoded.completedHoleScores, [3, -2])
        XCTAssertTrue(decoded.countsTowardStatistics)
    }

    func testMatchStatePersistenceBounds() {
        XCTAssertTrue(GolfMatchState(completedHoleScores: [-16, 35, 0]).isValidForPersistence)
        XCTAssertFalse(
            GolfMatchState(completedHoleScores: [36]).isValidForPersistence,
            "No hole can leave more strokes than the board deals"
        )
        XCTAssertFalse(
            GolfMatchState(completedHoleScores: [-17]).isValidForPersistence,
            "No clear can bank more than the full stock"
        )
        XCTAssertFalse(
            GolfMatchState(
                completedHoleScores: Array(repeating: 1, count: GolfMatchState.holeCount + 1)
            ).isValidForPersistence,
            "A match never records more than nine holes"
        )
    }

    // MARK: Match flow

    /// A one-card hole the session can win on demand: play the six onto the
    /// waste seven, leaving two stock cards banked (hole score −2).
    private func stageWinnableHole(on viewModel: SolitaireViewModel) {
        viewModel.state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .six)]],
            stock: [TestCards.make(.clubs, .nine), TestCards.make(.hearts, .two)],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        viewModel.configureGolfNewGame()
    }

    private func winStagedHole(on viewModel: SolitaireViewModel) {
        let selection = Selection(
            source: .tableau(pile: 0, index: viewModel.state.tableau[0].count - 1),
            cards: [viewModel.state.tableau[0].last!]
        )
        XCTAssertTrue(viewModel.performGolfMove(selection: selection, to: .waste))
        XCTAssertTrue(viewModel.isWin)
    }

    func testAdvanceRecordsHoleAndDealsNext() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        stageWinnableHole(on: viewModel)
        winStagedHole(on: viewModel)
        XCTAssertTrue(viewModel.isGolfHoleOver)
        XCTAssertEqual(viewModel.score, -2)

        viewModel.advanceGolfHole()

        XCTAssertEqual(viewModel.golfMatch.completedHoleScores, [-2])
        XCTAssertEqual(viewModel.golfMatch.currentHoleNumber, 2)
        XCTAssertFalse(viewModel.golfMatch.isComplete)
        XCTAssertEqual(
            viewModel.score,
            GolfGameRules.dealTableauCardCount,
            "Advancing deals a fresh hole with a fresh stroke score"
        )
        XCTAssertFalse(viewModel.isWin)
        XCTAssertFalse(viewModel.canUndo, "Undo can never cross a hole boundary")
    }

    func testAdvanceRequiresAFinishedHole() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        let before = viewModel.state

        viewModel.advanceGolfHole()

        XCTAssertEqual(viewModel.state, before, "A live hole cannot be advanced past")
        XCTAssertTrue(viewModel.golfMatch.completedHoleScores.isEmpty)
    }

    func testDeadHoleAdvancesWithPenaltyStrokes() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .ten)]],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        viewModel.configureGolfNewGame()
        XCTAssertTrue(viewModel.isGolfHoleDead)
        XCTAssertTrue(viewModel.isGolfHoleOver)
        XCTAssertEqual(viewModel.score, 1, "One card left on the board is one stroke")

        viewModel.advanceGolfHole()

        XCTAssertEqual(viewModel.golfMatch.completedHoleScores, [1])
        XCTAssertEqual(viewModel.golfMatch.currentHoleNumber, 2)
    }

    func testNinthHoleCompletesMatchWithoutDealing() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7, -2, 12, 0, 5, 9, 4]
        stageWinnableHole(on: viewModel)
        winStagedHole(on: viewModel)
        let boardAfterWin = viewModel.state
        let statsBefore = GameStatisticsStore.load(for: .golf)

        viewModel.advanceGolfHole()

        XCTAssertTrue(viewModel.golfMatch.isComplete)
        XCTAssertEqual(viewModel.golfMatch.runningTotal, 36)
        XCTAssertEqual(
            viewModel.state,
            boardAfterWin,
            "The match summary presents over the finished board — no tenth deal"
        )

        let statsAfter = GameStatisticsStore.load(for: .golf)
        XCTAssertEqual(statsAfter.golfMatchesCompleted, statsBefore.golfMatchesCompleted + 1)
        XCTAssertEqual(
            statsAfter.bestMatchTotal,
            min(statsBefore.bestMatchTotal ?? 36, 36),
            "Best match total records the lowest"
        )

        // Advancing again must not double-record the finished match.
        viewModel.advanceGolfHole()
        XCTAssertEqual(
            GameStatisticsStore.load(for: .golf).golfMatchesCompleted,
            statsAfter.golfMatchesCompleted
        )

        viewModel.startNewGolfMatch()
        XCTAssertEqual(viewModel.golfMatch, GolfMatchState())
        XCTAssertEqual(viewModel.golfMatch.currentHoleNumber, 1)
        XCTAssertFalse(viewModel.isWin)
    }

    func testCompletedMatchArchivesTheFinalBoard() {
        // Once the ninth hole banks, its board is an archive: the score is in
        // the scorecard and the statistics are recorded, so Undo and Redeal —
        // from any surface — must be inert. A dead ninth is the dangerous
        // case: unlike a won one, `isWin` doesn't gate anything.
        GameStatisticsStore.reset(for: .golf)
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7, -2, 12, 0, 5, 9, 4]
        viewModel.state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .six)], [TestCards.make(.hearts, .ten)]],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        viewModel.configureGolfNewGame()

        // A real move (the six onto the seven) kills the hole and leaves
        // undo history behind.
        let selection = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: [viewModel.state.tableau[0][0]]
        )
        XCTAssertTrue(viewModel.performGolfMove(selection: selection, to: .waste))
        XCTAssertTrue(viewModel.isGolfHoleDead)
        XCTAssertTrue(viewModel.canUndo, "A live dead hole may still be undone out of")

        viewModel.advanceGolfHole()
        XCTAssertTrue(viewModel.golfMatch.isComplete)
        let archivedBoard = viewModel.state
        let statsAfterMatch = GameStatisticsStore.load(for: .golf)

        XCTAssertFalse(viewModel.canUndo, "The banked board may not be mutated")
        viewModel.undo()
        XCTAssertEqual(viewModel.state, archivedBoard)

        XCTAssertFalse(viewModel.canRedeal, "Redeal would run a hidden deal under the summary")
        viewModel.redeal()
        XCTAssertEqual(viewModel.state, archivedBoard)

        // Starting the next match must not finalize any phantom deal the
        // blocked commands could have re-armed.
        viewModel.startNewGolfMatch()
        XCTAssertEqual(
            GameStatisticsStore.load(for: .golf).gamesPlayed,
            statsAfterMatch.gamesPlayed,
            "No hidden deal was started, so no extra loss records"
        )
    }

    func testFreshDealsAbandonTheMatch() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7]

        viewModel.newGame(mode: .klondikeDrawThree)
        XCTAssertEqual(viewModel.golfMatch, GolfMatchState())

        viewModel.newGame(mode: .golf)
        XCTAssertEqual(viewModel.golfMatch, GolfMatchState(), "A fresh deal starts at hole one")
    }

    func testActivatingAStashedSessionRestoresItsMatch() {
        // Game switching stashes each mode's session and re-activates it from
        // its payload, so leaving Golf and coming back resumes the match.
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7]
        let stashed = viewModel.persistencePayload()

        viewModel.activateGame(.klondikeDrawThree, restoringFrom: nil)
        XCTAssertEqual(viewModel.golfMatch, GolfMatchState())

        XCTAssertTrue(viewModel.activateGame(.golf, restoringFrom: stashed))
        XCTAssertEqual(
            viewModel.golfMatch.completedHoleScores,
            [3, 7],
            "Re-activating the stashed Golf session resumes the match"
        )

        // Without a stashed payload, activation falls back to a fresh deal
        // and a fresh match.
        viewModel.activateGame(.klondikeDrawThree, restoringFrom: nil)
        XCTAssertFalse(viewModel.activateGame(.golf, restoringFrom: nil))
        XCTAssertEqual(viewModel.golfMatch, GolfMatchState())
    }

    func testLiveMatchTotalIncludesTheActiveHole() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        XCTAssertEqual(
            viewModel.golfLiveMatchTotal,
            GolfGameRules.dealTableauCardCount,
            "On hole one, the live hole strokes are the whole match so far"
        )

        viewModel.golfMatch.completedHoleScores = [3, 7]
        stageWinnableHole(on: viewModel)
        XCTAssertEqual(viewModel.golfLiveMatchTotal, 11, "10 banked plus the staged hole's 1")

        winStagedHole(on: viewModel)
        XCTAssertEqual(viewModel.golfLiveMatchTotal, 8, "10 banked plus the won hole's −2")

        // Once the ninth hole banks, the live hole score is already in the
        // scorecard and must not double-count.
        viewModel.golfMatch.completedHoleScores = [3, 7, -2, 12, 0, 5, 9, 4, -2]
        XCTAssertEqual(viewModel.golfLiveMatchTotal, 36)
    }

    func testRedealKeepsTheMatchAndResetsStrokes() {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7]

        viewModel.redeal()

        XCTAssertEqual(
            viewModel.golfMatch.completedHoleScores,
            [3, 7],
            "Redeal replays the hole; the match stands"
        )
        XCTAssertEqual(viewModel.score, GolfGameRules.dealTableauCardCount)
    }

    // MARK: Statistics

    func testWonHoleRecordsBestHoleScore() {
        GameStatisticsStore.reset(for: .golf)
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        stageWinnableHole(on: viewModel)

        winStagedHole(on: viewModel)

        XCTAssertEqual(
            GameStatisticsStore.load(for: .golf).lowestScore,
            -2,
            "A won hole's final score records the moment the win finalizes"
        )
    }

    func testDeadHoleRecordsBestHoleScore() {
        // Strict Golf loses most holes; a dead hole is a completed hole and
        // its strokes belong in the best-hole record.
        GameStatisticsStore.reset(for: .golf)
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .ten)]],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        viewModel.configureGolfNewGame()
        XCTAssertTrue(viewModel.isGolfHoleDead)

        viewModel.advanceGolfHole()

        XCTAssertEqual(GameStatisticsStore.load(for: .golf).lowestScore, 1)
    }

    func testMidHoleAbandonDoesNotRecordBestHole() {
        // Abandoning a live hole finalizes a played game, but its score is an
        // unfinished snapshot — never a hole score.
        GameStatisticsStore.reset(for: .golf)
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        stageWinnableHole(on: viewModel)
        XCTAssertFalse(viewModel.isGolfHoleOver, "The staged hole still has a play available")

        viewModel.newGame(mode: .golf)

        let stats = GameStatisticsStore.load(for: .golf)
        XCTAssertGreaterThan(stats.gamesPlayed, 0, "The abandoned hole still counts as played")
        XCTAssertNil(stats.lowestScore)
    }

    func testDeadHolePauseKeepsOverlayDwellOutOfStatistics() {
        // A dead hole's time is final the moment nothing plays; the view
        // freezes the clock then, so however long the completion overlay
        // sits, only play time reaches the statistics.
        GameStatisticsStore.reset(for: .golf)
        let clock = TestDateProvider(now: DateFixtures.reference)
        let viewModel = SolitaireViewModel(dateProvider: clock, variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .ten)]],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        viewModel.configureGolfNewGame()
        XCTAssertTrue(viewModel.isGolfHoleDead)

        // The hole dies ten seconds in; the view pauses the clock…
        clock.now = DateFixtures.plus(10)
        XCTAssertTrue(viewModel.pauseTimeScoring(at: clock.now))

        // …and the overlay dwells another ninety before the player advances.
        clock.now = DateFixtures.plus(100)
        viewModel.advanceGolfHole()

        XCTAssertEqual(
            GameStatisticsStore.load(for: .golf).totalTimeSeconds,
            10,
            "Overlay dwell time is not play time"
        )
    }

    func testStatisticsResetMidMatchAbandonsTheAggregate() {
        GameStatisticsStore.reset(for: .golf)
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7, -2, 12, 0, 5, 9, 4]

        // The user resets statistics with the match on hole nine.
        GameStatisticsStore.reset(for: .golf)
        viewModel.resetStatisticsTracking()
        XCTAssertFalse(viewModel.golfMatch.countsTowardStatistics)

        stageWinnableHole(on: viewModel)
        winStagedHole(on: viewModel)
        viewModel.advanceGolfHole()

        XCTAssertTrue(viewModel.golfMatch.isComplete, "The match still plays to its end")
        let stats = GameStatisticsStore.load(for: .golf)
        XCTAssertEqual(
            stats.golfMatchesCompleted,
            0,
            "A match holding pre-reset holes must not finalize into the fresh bucket"
        )
        XCTAssertNil(stats.bestMatchTotal)

        // The next match is fully post-reset and records again.
        viewModel.startNewGolfMatch()
        XCTAssertTrue(viewModel.golfMatch.countsTowardStatistics)
    }

    // MARK: Persistence

    func testMatchSurvivesPayloadRoundTripMidHole() throws {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7, -2]

        let payload = viewModel.persistencePayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SavedGamePayload.self, from: data)

        let restored = SolitaireViewModel()
        XCTAssertTrue(restored.restore(from: decoded))
        XCTAssertEqual(restored.golfMatch.completedHoleScores, [3, 7, -2])
        XCTAssertEqual(restored.golfMatch.currentHoleNumber, 4)
    }

    func testLegacyPayloadWithoutMatchRestoresAFreshOne() throws {
        let payload = SavedGamePayload(
            state: GameState.newGolfGame(),
            movesCount: 0,
            stockDrawCount: DrawMode.one.rawValue,
            history: []
        )
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(payload)
        ) as? [String: Any] ?? [:]
        json.removeValue(forKey: "golfMatch")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(SavedGamePayload.self, from: data)

        let restored = SolitaireViewModel()
        XCTAssertTrue(restored.restore(from: decoded))
        XCTAssertEqual(restored.golfMatch, GolfMatchState())
    }

    func testSanitizerDropsForeignAndCorruptMatches() throws {
        // A non-Golf payload never carries a match.
        let klondikePayload = SavedGamePayload(
            state: GameStateFixtures.seededKlondikeDeal(seed: 1),
            movesCount: 0,
            stockDrawCount: DrawMode.three.rawValue,
            history: [],
            golfMatch: GolfMatchState(completedHoleScores: [3])
        )
        let sanitizedKlondike = try XCTUnwrap(
            klondikePayload.sanitizedForRestore(at: DateFixtures.reference)
        )
        XCTAssertNil(sanitizedKlondike.golfMatch)

        // A structurally impossible scorecard drops to a fresh match.
        let corruptPayload = SavedGamePayload(
            state: GameState.newGolfGame(),
            movesCount: 0,
            stockDrawCount: DrawMode.one.rawValue,
            history: [],
            golfMatch: GolfMatchState(completedHoleScores: [99])
        )
        let sanitizedCorrupt = try XCTUnwrap(
            corruptPayload.sanitizedForRestore(at: DateFixtures.reference)
        )
        XCTAssertNil(sanitizedCorrupt.golfMatch)

        // A legal mid-match scorecard survives, negatives included.
        let legalPayload = SavedGamePayload(
            state: GameState.newGolfGame(),
            movesCount: 0,
            stockDrawCount: DrawMode.one.rawValue,
            history: [],
            golfMatch: GolfMatchState(completedHoleScores: [3, -2])
        )
        let sanitizedLegal = try XCTUnwrap(
            legalPayload.sanitizedForRestore(at: DateFixtures.reference)
        )
        XCTAssertEqual(sanitizedLegal.golfMatch?.completedHoleScores, [3, -2])
    }

    func testTrackingResetPreservesTheScorecardButRevokesEligibility() {
        // Resetting statistics invalidates every stashed session's tracking;
        // the Golf scorecard is gameplay progress and must survive the copy
        // with only its statistics eligibility revoked.
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = [3, 7, -2]

        let reset = viewModel.persistencePayload().withStatisticsTrackingReset()

        XCTAssertEqual(reset.golfMatch?.completedHoleScores, [3, 7, -2])
        XCTAssertEqual(reset.golfMatch?.countsTowardStatistics, false)
        XCTAssertFalse(reset.hasStartedTrackedGame)

        // The revoked eligibility survives restore sanitization too.
        let restored = SolitaireViewModel()
        XCTAssertTrue(restored.restore(from: reset))
        XCTAssertEqual(restored.golfMatch.completedHoleScores, [3, 7, -2])
        XCTAssertFalse(restored.golfMatch.countsTowardStatistics)
    }

    func testCompletedMatchSurvivesRestoreForTheSummary() throws {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        viewModel.golfMatch.completedHoleScores = Array(repeating: 4, count: GolfMatchState.holeCount)

        let payload = viewModel.persistencePayload()
        let restored = SolitaireViewModel()
        XCTAssertTrue(restored.restore(from: payload))
        XCTAssertTrue(
            restored.golfMatch.isComplete,
            "Quitting at the summary re-presents it on relaunch"
        )
    }

    // MARK: Formatting

    func testParStandingFormatting() {
        XCTAssertEqual(
            GolfScoreFormatting.parStanding(total: 45, holesPlayed: 9),
            "Total 45 — even with par"
        )
        XCTAssertEqual(
            GolfScoreFormatting.parStanding(total: 42, holesPlayed: 9),
            "Total 42 — 3 under par"
        )
        XCTAssertEqual(
            GolfScoreFormatting.parStanding(total: 50, holesPlayed: 9),
            "Total 50 — 5 over par"
        )
        XCTAssertEqual(
            GolfScoreFormatting.parStanding(total: 11, holesPlayed: 3),
            "Total 11 — 4 under par pace"
        )
    }
}
