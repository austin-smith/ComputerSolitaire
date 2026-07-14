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

    func testSanitizedForRestoreRejectsKlondikeStateWithStrandedFreeCellCard() {
        // Klondike renders no free-cell slots, so a card stranded there would be
        // invisible and the game unwinnable.
        var state = GameStateFixtures.validPersistenceState()
        state.freeCells[0] = state.stock.removeLast()
        XCTAssertNil(makePayload(state: state).sanitizedForRestore())
    }

    func testEveryOtherVariantLayoutRuleRejectsStrandedReserveCards() {
        // Canfield's reserve belongs to that variant alone: the census counts
        // it, so without a layout guard a card smuggled there would keep a
        // valid card count while being invisible everywhere else. The layout
        // rules are census-independent, so the guard is checked in isolation:
        // the same deal must flip from valid to rejected on the reserve alone.
        let layoutRule: [GameVariant: (GameState) -> Bool] = [
            .klondike: KlondikePersistenceRules.hasValidLayout,
            .freecell: FreeCellPersistenceRules.hasValidLayout,
            .yukon: YukonPersistenceRules.hasValidLayout,
            .spider: SpiderPersistenceRules.hasValidLayout,
            .pyramid: PyramidPersistenceRules.hasValidLayout,
            .tripeaks: TriPeaksPersistenceRules.hasValidLayout,
            .golf: GolfPersistenceRules.hasValidLayout,
            .fortyThieves: FortyThievesPersistenceRules.hasValidLayout,
            .scorpion: ScorpionPersistenceRules.hasValidLayout
        ]
        let deal: [GameVariant: GameState] = [
            .klondike: GameStateFixtures.seededKlondikeDeal(seed: 5),
            .freecell: GameStateFixtures.seededFreeCellDeal(seed: 5),
            .yukon: GameStateFixtures.seededYukonDeal(seed: 5),
            .spider: GameStateFixtures.seededSpiderDeal(seed: 5, suitCount: .two),
            .pyramid: GameStateFixtures.seededPyramidDeal(seed: 5),
            .tripeaks: GameStateFixtures.seededTriPeaksDeal(seed: 5),
            .golf: GameStateFixtures.seededGolfDeal(seed: 5),
            .fortyThieves: GameStateFixtures.seededFortyThievesDeal(seed: 5),
            .scorpion: GameStateFixtures.seededScorpionDeal(seed: 5)
        ]

        for variant in GameVariant.allCases where variant != .canfield {
            guard let rule = layoutRule[variant], var state = deal[variant] else {
                XCTFail("\(variant): missing layout rule or deal fixture")
                continue
            }
            XCTAssertTrue(rule(state), "\(variant): the untouched deal must pass its layout rule")
            state.reserve = [TestCards.make(.spades, .ace, isFaceUp: false)]
            XCTAssertFalse(rule(state), "\(variant): a card stranded in the reserve must be rejected")
        }
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
