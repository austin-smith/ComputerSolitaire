import XCTest
@testable import Computer_Solitaire

@MainActor
final class GolfSessionTests: XCTestCase {
    private func makeGolfSession() -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.newGame(mode: .golf)
        return viewModel
    }

    /// A session staged on a hand-constructed board; draw counts and the
    /// initial stroke score configured as a real Golf game would be.
    private func makeStagedSession(state: GameState) -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .golf)
        viewModel.state = state
        viewModel.configureGolfNewGame()
        return viewModel
    }

    private func exposedSelection(column: Int, in viewModel: SolitaireViewModel) -> Selection {
        Selection(
            source: .tableau(pile: column, index: viewModel.state.tableau[column].count - 1),
            cards: [viewModel.state.tableau[column].last!]
        )
    }

    func testNewGolfGameLayout() {
        let state = GameState.newGolfGame()
        XCTAssertEqual(state.variant, .golf)
        XCTAssertEqual(state.tableau.count, GolfGameRules.columnCount)
        XCTAssertTrue(state.tableau.allSatisfy { $0.count == GolfGameRules.columnDepth })
        XCTAssertTrue(state.tableau.allSatisfy { $0.allSatisfy(\.isFaceUp) })
        XCTAssertEqual(state.stock.count, GolfGameRules.dealStockCardCount)
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertEqual(state.waste.count, 1)
        XCTAssertEqual(state.waste.last?.isFaceUp, true)
        XCTAssertEqual(state.wasteDrawCount, 1)
        XCTAssertTrue(state.pyramid.isEmpty)
        XCTAssertTrue(state.triPeaks.isEmpty)
        XCTAssertTrue(state.discard.isEmpty)
        XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
        XCTAssertFalse(state.isWon)
    }

    func testSeededDealMatchesRealDealShape() {
        let real = GameState.newGolfGame()
        let seeded = GameStateFixtures.seededGolfDeal(seed: 1)
        XCTAssertEqual(seeded.tableau.count, real.tableau.count)
        XCTAssertEqual(seeded.tableau.map(\.count), real.tableau.map(\.count))
        XCTAssertEqual(seeded.stock.count, real.stock.count)
        XCTAssertEqual(seeded.waste.count, real.waste.count)
        XCTAssertEqual(seeded.wasteDrawCount, real.wasteDrawCount)
        XCTAssertTrue(seeded.tableau.allSatisfy { $0.allSatisfy(\.isFaceUp) })
    }

    func testNewGameConfiguresDrawCountsAndInitialScore() {
        let viewModel = makeGolfSession()
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(viewModel.scoringDrawCount, DrawMode.three.rawValue)
        XCTAssertFalse(viewModel.supportsDrawMode)
        XCTAssertEqual(
            viewModel.score,
            GolfGameRules.dealTableauCardCount,
            "The stroke score starts at one per board card"
        )
    }

    func testPlayReducesScoreByOneAndPushesUndo() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [
                    [TestCards.make(.spades, .nine), TestCards.make(.hearts, .seven)],
                    [TestCards.make(.clubs, .jack)]
                ],
                waste: [TestCards.make(.diamonds, .six)],
                fillWasteFromRemainder: true
            )
        )
        XCTAssertEqual(viewModel.score, 3)

        XCTAssertTrue(viewModel.performGolfMove(
            selection: exposedSelection(column: 0, in: viewModel),
            to: .waste
        ))

        XCTAssertEqual(viewModel.score, 2, "One card left the board")
        XCTAssertEqual(viewModel.state.waste.last?.rank, .seven)
        XCTAssertEqual(viewModel.movesCount, 1)

        viewModel.undo()
        XCTAssertEqual(viewModel.score, 3)
        XCTAssertEqual(viewModel.state.tableau[0].count, 2)
    }

    func testStockTapDrawsOneCardAndScoresNothing() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [[TestCards.make(.spades, .ten)]],
                stock: [TestCards.make(.clubs, .nine)],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )
        let scoreBefore = viewModel.score

        viewModel.handleStockTap()

        XCTAssertTrue(viewModel.state.stock.isEmpty)
        XCTAssertEqual(viewModel.state.waste.last?.rank, .nine)
        XCTAssertEqual(viewModel.state.waste.last?.isFaceUp, true)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1)
        XCTAssertEqual(viewModel.score, scoreBefore, "A stock flip costs no strokes")
        XCTAssertEqual(viewModel.movesCount, 1)

        viewModel.undo()
        XCTAssertEqual(viewModel.state.stock.count, 1)
    }

    func testStockExhaustsWithNoRecycle() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [[TestCards.make(.spades, .ten)]],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )
        XCTAssertFalse(viewModel.canInteractWithStock, "An empty Golf stock is dead")

        let movesBefore = viewModel.movesCount
        let before = viewModel.state
        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.state, before, "An empty stock never recycles")
        XCTAssertEqual(viewModel.movesCount, movesBefore)
        XCTAssertFalse(viewModel.canUndo, "A dead stock tap must not push history")
    }

    func testWinningMoveBanksStockBonusIntoNegativeScoreWithNoTimeBonus() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [[TestCards.make(.spades, .six)]],
                stock: [
                    TestCards.make(.clubs, .nine),
                    TestCards.make(.hearts, .two),
                    TestCards.make(.clubs, .king)
                ],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )
        XCTAssertEqual(viewModel.score, 1)

        XCTAssertTrue(viewModel.performGolfMove(
            selection: exposedSelection(column: 0, in: viewModel),
            to: .waste
        ))

        XCTAssertTrue(viewModel.isWin, "Clearing the last column card wins with stock remaining")
        XCTAssertEqual(
            viewModel.score,
            -3,
            "The final play removes the last stroke and banks one per leftover stock card"
        )
        XCTAssertEqual(viewModel.displayScore(), -3, "No time bonus ever pads a Golf score")
        XCTAssertNotNil(viewModel.finalElapsedSeconds, "The win still stops the clock")
    }

    func testTapQueuesAutoMoveToWaste() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [[TestCards.make(.spades, .six)]],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )

        viewModel.handleTableauTap(pileIndex: 0, cardIndex: 0)

        XCTAssertEqual(viewModel.pendingAutoMove?.destination, .waste)
        XCTAssertEqual(viewModel.pendingAutoMove?.selection.source, .tableau(pile: 0, index: 0))
        XCTAssertNil(viewModel.selection, "Golf has no two-step selection flow")
    }

    func testTappingBuriedOrUnplayableCardsQueuesNothing() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [
                    [TestCards.make(.spades, .six), TestCards.make(.hearts, .ten)]
                ],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )
        let before = viewModel.state

        viewModel.handleTableauTap(pileIndex: 0, cardIndex: 0)
        XCTAssertEqual(viewModel.state, before, "A buried card ignores taps")
        XCTAssertNil(viewModel.pendingAutoMove)
        XCTAssertNil(viewModel.selection)

        viewModel.handleTableauTap(pileIndex: 0, cardIndex: 1)
        XCTAssertEqual(viewModel.state, before, "An unplayable exposed card gives feedback only")
        XCTAssertNil(viewModel.pendingAutoMove)
        XCTAssertNil(viewModel.selection)
    }

    func testWasteTapAndDragAreInert() {
        let viewModel = makeGolfSession()
        let before = viewModel.state

        viewModel.handleWasteTap()
        XCTAssertEqual(viewModel.state, before)
        XCTAssertNil(viewModel.selection, "The waste top is a target, never a mover")

        XCTAssertFalse(viewModel.startDragFromWaste())
        XCTAssertFalse(viewModel.isDragging)
    }

    func testDragRequiresExposedCard() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [
                    [TestCards.make(.spades, .six), TestCards.make(.hearts, .ten)]
                ],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )

        XCTAssertFalse(
            viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 0),
            "Buried cards cannot drag"
        )
        XCTAssertTrue(
            viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 1),
            "Any exposed card can drag; playability is checked at the drop"
        )
        XCTAssertEqual(viewModel.selection?.cards.count, 1)
        XCTAssertTrue(viewModel.isDragging)
        XCTAssertFalse(viewModel.canDrop(to: .waste), "Ten is not adjacent to seven")

        viewModel.selection = exposedSelection(column: 0, in: viewModel)
        XCTAssertFalse(
            viewModel.canDrop(to: .tableau(1)),
            "Golf columns are never a destination"
        )
    }

    func testDropOnWasteFollowsAdjacency() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.golfState(
                columns: [
                    [TestCards.make(.spades, .six)],
                    [TestCards.make(.hearts, .king)]
                ],
                waste: [TestCards.make(.diamonds, .seven)],
                fillWasteFromRemainder: true
            )
        )

        viewModel.selection = exposedSelection(column: 0, in: viewModel)
        XCTAssertTrue(viewModel.canDrop(to: .waste))

        viewModel.selection = exposedSelection(column: 1, in: viewModel)
        XCTAssertFalse(viewModel.canDrop(to: .waste), "King is not adjacent to seven")
    }

    func testHintAvailabilityTracksStockAndAdjacency() {
        let withStock = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .ten)]],
            stock: [TestCards.make(.clubs, .nine)],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        XCTAssertTrue(
            HintAdvisor.anyPlayerMoveExists(in: withStock),
            "A flip is a legal action while stock remains"
        )

        let deadBoard = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .ten)]],
            waste: [TestCards.make(.diamonds, .seven)],
            fillWasteFromRemainder: true
        )
        XCTAssertFalse(
            HintAdvisor.anyPlayerMoveExists(in: deadBoard),
            "Empty stock and no adjacent play: nothing is legal"
        )
    }

    func testRedealRestoresDealAndStrokes() {
        let viewModel = makeGolfSession()
        let dealtState = viewModel.state

        let playable = AutoMoveAdvisor.candidateSelections(in: viewModel.state).first { selection in
            !AutoMoveAdvisor.legalDestinations(for: selection, in: viewModel.state).isEmpty
        }
        if let playable {
            XCTAssertTrue(viewModel.performGolfMove(selection: playable, to: .waste))
        } else {
            viewModel.handleStockTap()
        }
        XCTAssertNotEqual(viewModel.state, dealtState)

        viewModel.redeal()

        XCTAssertEqual(viewModel.state, dealtState, "Redeal replays the same deal")
        XCTAssertEqual(
            viewModel.score,
            GolfGameRules.dealTableauCardCount,
            "Redeal resets the stroke score to the board count"
        )
    }
}
