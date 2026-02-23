import XCTest
@testable import Computer_Solitaire

@MainActor
final class SolitaireViewModelCoreTests: XCTestCase {
    private static var retainedViewModels: [SolitaireViewModel] = []

    func testNewGameResetsCoreStateAndAppliesDrawMode() {
        let viewModel = makeViewModel()
        viewModel.newGame(drawMode: .one)

        XCTAssertEqual(viewModel.movesCount, 0)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertNil(viewModel.selection)
        XCTAssertFalse(viewModel.isDragging)
        XCTAssertNil(viewModel.pendingAutoMove)
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(viewModel.visibleWasteCards().count, 0)
        XCTAssertTrue(viewModel.isClockAdvancing)
    }

    func testHandleStockTapDrawsCardsFromStock() {
        let state = makeValidState(
            stock: [
                TestCards.make(.clubs, .ace, isFaceUp: false),
                TestCards.make(.diamonds, .ace, isFaceUp: false),
                TestCards.make(.hearts, .ace, isFaceUp: false)
            ],
            waste: [],
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7)
        )
        let viewModel = makeViewModel(restoring: payload(state: state, stockDrawCount: DrawMode.three.rawValue))

        let stockBefore = viewModel.state.stock.count
        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.stock.count, stockBefore - 3)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 3)
        XCTAssertGreaterThanOrEqual(viewModel.state.waste.count, 3)
        XCTAssertTrue(viewModel.visibleWasteCards().allSatisfy(\.isFaceUp))
        XCTAssertEqual(viewModel.state.wasteDrawCount, 3)
        XCTAssertEqual(viewModel.movesCount, 1)
        XCTAssertEqual(viewModel.visibleWasteCards().count, min(3, viewModel.state.waste.count))
    }

    func testHandleStockTapRecyclesWasteWhenStockEmpty() {
        var state = GameStateFixtures.validPersistenceState()
        state.waste = state.stock.map { card in
            var faceUp = card
            faceUp.isFaceUp = true
            return faceUp
        }
        state.stock = []
        state.wasteDrawCount = min(3, state.waste.count)
        let viewModel = makeViewModel(restoring: payload(state: state, stockDrawCount: DrawMode.one.rawValue))

        viewModel.handleStockTap()

        XCTAssertGreaterThan(viewModel.state.stock.count, 0)
        XCTAssertEqual(viewModel.state.waste.count, 0)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 0)
        XCTAssertEqual(viewModel.movesCount, 1)
        XCTAssertEqual(viewModel.score, 0, "Recycle in draw-one clamps at minimum score")
        XCTAssertTrue(viewModel.state.stock.allSatisfy { !$0.isFaceUp })
    }

    func testStartDragCanDropAndHandleDropMoveWasteToFoundation() {
        let aceSpades = TestCards.make(.spades, .ace, isFaceUp: true)
        let state = makeValidState(
            stock: [],
            waste: [aceSpades],
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7),
            wasteDrawCount: 1
        )
        let viewModel = makeViewModel(restoring: payload(state: state, stockDrawCount: DrawMode.three.rawValue))

        XCTAssertTrue(viewModel.startDragFromWaste())
        XCTAssertTrue(viewModel.canDrop(to: .foundation(0)))
        XCTAssertTrue(viewModel.handleDrop(to: .foundation(0)))

        XCTAssertEqual(viewModel.state.waste.count, 0)
        XCTAssertEqual(viewModel.state.foundations[0].last?.id, aceSpades.id)
        XCTAssertEqual(viewModel.movesCount, 1)
        XCTAssertEqual(viewModel.score, Scoring.delta(for: .wasteToFoundation))
        XCTAssertNil(viewModel.selection)
        XCTAssertFalse(viewModel.isDragging)
    }

    func testUndoRestoresPriorSnapshotAfterMove() {
        let aceSpades = TestCards.make(.spades, .ace, isFaceUp: true)
        let state = makeValidState(
            stock: [],
            waste: [aceSpades],
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7),
            wasteDrawCount: 1
        )
        let viewModel = makeViewModel(restoring: payload(state: state, stockDrawCount: DrawMode.three.rawValue))

        XCTAssertTrue(viewModel.startDragFromWaste())
        XCTAssertTrue(viewModel.handleDrop(to: .foundation(0)))
        XCTAssertEqual(viewModel.movesCount, 1)

        viewModel.undo()

        XCTAssertEqual(viewModel.movesCount, 0)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertEqual(viewModel.state.waste.last?.id, aceSpades.id)
        XCTAssertTrue(viewModel.state.foundations[0].isEmpty)
    }

    func testPauseResumeAndElapsedTimeAccounting() {
        let clock = TestDateProvider(now: DateFixtures.reference)
        let viewModel = makeViewModel(dateProvider: clock)
        viewModel.newGame(drawMode: .three)

        let start = DateFixtures.plus(-600)
        clock.now = DateFixtures.plus(120)
        let restore = payload(
            state: viewModel.state,
            savedAt: DateFixtures.plus(100),
            stockDrawCount: DrawMode.three.rawValue,
            gameStartedAt: start,
            pauseStartedAt: nil
        )
        XCTAssertTrue(viewModel.restore(from: restore))

        // elapsed at restore should match active play time at save.
        // start=-600, savedAt=100 => 700 seconds of active time.
        XCTAssertEqual(viewModel.elapsedActiveSeconds(at: clock.now), 700)

        XCTAssertTrue(viewModel.pauseTimeScoring(at: DateFixtures.plus(130)))
        XCTAssertEqual(viewModel.elapsedActiveSeconds(at: DateFixtures.plus(180)), 710)

        XCTAssertTrue(viewModel.resumeTimeScoring(at: DateFixtures.plus(200)))
        XCTAssertEqual(viewModel.elapsedActiveSeconds(at: DateFixtures.plus(260)), 770)
        XCTAssertEqual(viewModel.displayScore(at: DateFixtures.plus(260)), Scoring.timedMaxBonusDrawThree - 770)
    }

    func testQueueNextAutoFinishMoveSetsPendingMove() {
        let viewModel = makeViewModel(
            restoring: payload(
                state: GameStateFixtures.almostWonForAutoFinish(),
                stockDrawCount: DrawMode.three.rawValue
            )
        )

        XCTAssertTrue(viewModel.isAutoFinishAvailable)
        XCTAssertTrue(viewModel.queueNextAutoFinishMove())
        XCTAssertNotNil(viewModel.pendingAutoMove)
    }

    private func makeViewModel(
        dateProvider: any DateProviding = SystemDateProvider(),
        restoring payload: SavedGamePayload? = nil
    ) -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(dateProvider: dateProvider)
        if let payload {
            XCTAssertTrue(viewModel.restore(from: payload))
        }
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }

    private func payload(
        state: GameState,
        savedAt: Date = DateFixtures.reference,
        stockDrawCount: Int,
        gameStartedAt: Date = DateFixtures.reference,
        pauseStartedAt: Date? = nil
    ) -> SavedGamePayload {
        SavedGamePayload(
            savedAt: savedAt,
            state: state,
            movesCount: 0,
            score: 0,
            gameStartedAt: gameStartedAt,
            pauseStartedAt: pauseStartedAt,
            hasAppliedTimeBonus: false,
            finalElapsedSeconds: nil,
            stockDrawCount: stockDrawCount,
            scoringDrawCount: stockDrawCount,
            history: [],
            redealState: state,
            hasStartedTrackedGame: true,
            isCurrentGameFinalized: false,
            hintRequestsInCurrentGame: 0,
            undosUsedInCurrentGame: 0,
            usedRedealInCurrentGame: false
        )
    }

    private func makeValidState(
        stock: [Card],
        waste: [Card],
        foundations: [[Card]],
        tableau: [[Card]],
        wasteDrawCount: Int = 0
    ) -> GameState {
        var usedBySuitRank = Set(stock.map { "\($0.suit)-\($0.rank.rawValue)" })
        for card in waste {
            usedBySuitRank.insert("\(card.suit)-\(card.rank.rawValue)")
        }
        for pile in foundations {
            for card in pile {
                usedBySuitRank.insert("\(card.suit)-\(card.rank.rawValue)")
            }
        }
        for pile in tableau {
            for card in pile {
                usedBySuitRank.insert("\(card.suit)-\(card.rank.rawValue)")
            }
        }

        let filler = TestCards.fullDeck(faceUp: false).filter {
            !usedBySuitRank.contains("\($0.suit)-\($0.rank.rawValue)")
        }
        let finalStock = stock + filler

        return GameState(
            stock: finalStock,
            waste: waste,
            wasteDrawCount: min(max(0, wasteDrawCount), waste.count),
            foundations: foundations,
            tableau: tableau
        )
    }
}
