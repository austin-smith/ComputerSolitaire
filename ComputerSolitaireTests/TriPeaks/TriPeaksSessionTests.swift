import XCTest
@testable import Computer_Solitaire

@MainActor
final class TriPeaksSessionTests: XCTestCase {
    private func makeTriPeaksSession() -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .tripeaks)
        viewModel.newGame(mode: .tripeaks)
        return viewModel
    }

    /// A session staged on a hand-constructed board; draw counts configured as
    /// a real TriPeaks game would be.
    private func makeStagedSession(state: GameState) -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .tripeaks)
        viewModel.state = state
        viewModel.configureTriPeaksNewGame()
        return viewModel
    }

    private func playedSelection(at index: Int, in viewModel: SolitaireViewModel) -> Selection {
        Selection(source: .triPeaks(index: index), cards: [viewModel.state.triPeaks[index]!])
    }

    func testNewTriPeaksGameLayout() {
        let state = GameState.newTriPeaksGame()
        XCTAssertEqual(state.variant, .tripeaks)
        XCTAssertEqual(state.triPeaks.count, TriPeaksGeometry.cardCount)
        for index in state.triPeaks.indices {
            let expectedFaceUp = TriPeaksGeometry.row(of: index) == TriPeaksGeometry.rowCount - 1
            XCTAssertEqual(
                state.triPeaks[index]?.isFaceUp,
                expectedFaceUp,
                "Rows above the base deal face down; the base row deals face up"
            )
        }
        XCTAssertEqual(state.stock.count, 23)
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertEqual(state.waste.count, 1)
        XCTAssertEqual(state.waste.last?.isFaceUp, true)
        XCTAssertEqual(state.wasteDrawCount, 1)
        XCTAssertTrue(state.tableau.isEmpty)
        XCTAssertTrue(state.pyramid.isEmpty)
        XCTAssertTrue(state.discard.isEmpty)
        XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
        XCTAssertEqual(state.triPeaksChainLength, 0)
        XCTAssertFalse(state.isWon)
    }

    func testSeededDealMatchesRealDealShape() {
        let real = GameState.newTriPeaksGame()
        let seeded = GameStateFixtures.seededTriPeaksDeal(seed: 1)
        XCTAssertEqual(seeded.triPeaks.count, real.triPeaks.count)
        XCTAssertEqual(seeded.stock.count, real.stock.count)
        XCTAssertEqual(seeded.waste.count, real.waste.count)
        XCTAssertEqual(seeded.wasteDrawCount, real.wasteDrawCount)
        for index in seeded.triPeaks.indices {
            XCTAssertEqual(seeded.triPeaks[index]?.isFaceUp, real.triPeaks[index]?.isFaceUp)
        }
    }

    func testNewGameConfiguresDrawCounts() {
        let viewModel = makeTriPeaksSession()
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(viewModel.scoringDrawCount, DrawMode.three.rawValue)
        XCTAssertFalse(viewModel.supportsDrawMode)
    }

    func testStockTapDrawsOneCardResetsChainAndScoresPenalty() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                stock: [TestCards.make(.clubs, .nine, isFaceUp: false)],
                waste: [TestCards.make(.diamonds, .seven)],
                chainLength: 4
            )
        )
        viewModel.setInitialScore(20)

        viewModel.handleStockTap()

        XCTAssertTrue(viewModel.state.stock.isEmpty)
        XCTAssertEqual(viewModel.state.waste.last?.rank, .nine)
        XCTAssertEqual(viewModel.state.waste.last?.isFaceUp, true)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1)
        XCTAssertEqual(viewModel.state.triPeaksChainLength, 0, "A stock flip breaks the chain")
        XCTAssertEqual(viewModel.score, 15, "A stock flip costs five points")
        XCTAssertEqual(viewModel.movesCount, 1)

        viewModel.undo()
        XCTAssertEqual(viewModel.state.stock.count, 1)
        XCTAssertEqual(viewModel.state.triPeaksChainLength, 4)
        XCTAssertEqual(viewModel.score, 20)
    }

    func testStockFlipScoreClampsAtZero() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                stock: [TestCards.make(.clubs, .nine, isFaceUp: false)],
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )
        viewModel.setInitialScore(3)

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.score, 0, "Score never goes below zero")
    }

    func testPlayMovesScoreChainEscalationAndFlipResetsIt() {
        // Base 6, 5, 4 chain off the waste 7; the stock flip in between breaks
        // the chain so the final play scores 1 again. The unplayable Jack keeps
        // the board from clearing so no win bonus muddies the arithmetic.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .five)
        slots[20] = TestCards.make(.clubs, .four)
        slots[27] = TestCards.make(.diamonds, .jack)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                stock: [TestCards.make(.clubs, .five, isFaceUp: false)],
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )

        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 18, in: viewModel),
            to: .waste
        ))
        XCTAssertEqual(viewModel.score, 1, "First discard in a chain scores one")

        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 19, in: viewModel),
            to: .waste
        ))
        XCTAssertEqual(viewModel.score, 3, "Second discard scores two")

        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.score, 0, "Flip costs five, clamped at zero")
        XCTAssertEqual(viewModel.state.triPeaksChainLength, 0)

        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 20, in: viewModel),
            to: .waste
        ))
        XCTAssertEqual(viewModel.score, 1, "The chain restarts at one after a flip")
    }

    func testPeakClearAwardsBonus() {
        // Apex 0 is the only card of its peak; apex 1 remains, so clearing apex
        // 0 pays the peak bonus, not the board-clear bonus.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[0] = TestCards.make(.spades, .six)
        slots[1] = TestCards.make(.hearts, .jack)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                stock: [TestCards.make(.clubs, .nine, isFaceUp: false)],
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )

        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 0, in: viewModel),
            to: .waste
        ))
        XCTAssertEqual(viewModel.score, 16, "Chain point plus the 15-point peak bonus")
        XCTAssertFalse(viewModel.isWin)
    }

    func testBoardClearAwardsThirtyAndWinsWithStockRemaining() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[0] = TestCards.make(.spades, .six)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                stock: [TestCards.make(.clubs, .nine, isFaceUp: false)],
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )

        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 0, in: viewModel),
            to: .waste
        ))

        XCTAssertTrue(viewModel.isWin, "Clearing the last peak card wins with stock remaining")
        let timeBonus = Scoring.timeBonus(
            elapsedSeconds: viewModel.finalElapsedSeconds ?? 0,
            maxBonus: Scoring.timedMaxBonusDrawThree
        )
        XCTAssertEqual(
            viewModel.score,
            1 + 30 + timeBonus,
            "Chain point, board-clear bonus, and the draw-three-basis time bonus"
        )
    }

    func testTapQueuesAutoMoveToWaste() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )

        viewModel.handleTriPeaksTap(index: 18)

        XCTAssertEqual(viewModel.pendingAutoMove?.destination, .waste)
        XCTAssertEqual(viewModel.pendingAutoMove?.selection.source, .triPeaks(index: 18))
    }

    func testTappingCoveredOrUnplayableCardsDoesNothing() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[9] = TestCards.make(.clubs, .eight)
        slots[18] = TestCards.make(.spades, .ten)
        slots[19] = TestCards.make(.hearts, .three)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )
        let before = viewModel.state

        viewModel.handleTriPeaksTap(index: 9)
        XCTAssertEqual(viewModel.state, before, "A covered card ignores taps")
        XCTAssertNil(viewModel.pendingAutoMove)
        XCTAssertNil(viewModel.selection)

        viewModel.handleTriPeaksTap(index: 18)
        XCTAssertEqual(viewModel.state, before, "An unplayable card gives feedback only")
        XCTAssertNil(viewModel.pendingAutoMove)
        XCTAssertNil(viewModel.selection, "TriPeaks has no two-step selection flow")
    }

    func testWasteTapAndDragAreInert() {
        let viewModel = makeTriPeaksSession()
        let before = viewModel.state

        viewModel.handleWasteTap()
        XCTAssertEqual(viewModel.state, before)
        XCTAssertNil(viewModel.selection, "The waste top is a target, never a mover")

        XCTAssertFalse(viewModel.startDragFromWaste())
        XCTAssertFalse(viewModel.isDragging)
    }

    func testDragFromPeaksRequiresUncoveredFaceUpCard() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[9] = TestCards.make(.clubs, .eight)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .ten)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )

        XCTAssertFalse(viewModel.startDragFromTriPeaks(index: 9), "Covered cards cannot drag")
        XCTAssertTrue(
            viewModel.startDragFromTriPeaks(index: 19),
            "Any uncovered card can drag; playability is checked at the drop"
        )
        XCTAssertEqual(viewModel.selection?.source, .triPeaks(index: 19))
        XCTAssertTrue(viewModel.isDragging)
        XCTAssertFalse(viewModel.canDrop(to: .waste), "Ten is not adjacent to seven")

        viewModel.selection = Selection(
            source: .triPeaks(index: 18),
            cards: [viewModel.state.triPeaks[18]!]
        )
        XCTAssertTrue(viewModel.canDrop(to: .waste))
    }

    func testStockExhaustsWithNoRecycle() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .six)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )
        XCTAssertFalse(viewModel.canInteractWithStock, "An empty TriPeaks stock is dead")

        let movesBefore = viewModel.movesCount
        let before = viewModel.state
        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.state, before, "An empty stock never recycles")
        XCTAssertEqual(viewModel.movesCount, movesBefore)
        XCTAssertFalse(viewModel.canUndo, "A dead stock tap must not push history")
    }

    func testUndoRestoresFlippedCardsFaceDown() {
        // Playing the 6 then the 5 (a chain) removes both coverers of slot 9.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[9] = TestCards.make(.clubs, .queen)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .five)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.triPeaksState(
                slots: slots,
                waste: [TestCards.make(.diamonds, .seven)]
            )
        )

        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 18, in: viewModel),
            to: .waste
        ))
        XCTAssertTrue(viewModel.performTriPeaksMove(
            selection: playedSelection(at: 19, in: viewModel),
            to: .waste
        ))
        XCTAssertEqual(viewModel.state.triPeaks[9]?.isFaceUp, true)

        viewModel.undo()
        XCTAssertEqual(
            viewModel.state.triPeaks[9]?.isFaceUp,
            false,
            "Undo restores the auto-flipped card face down"
        )
        XCTAssertNotNil(viewModel.state.triPeaks[19])
        XCTAssertEqual(viewModel.state.triPeaksChainLength, 1)
    }

    func testHintAvailabilityTracksStock() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[18] = TestCards.make(.spades, .ten)

        let withStock = GameStateFixtures.triPeaksState(
            slots: slots,
            stock: [TestCards.make(.clubs, .nine, isFaceUp: false)],
            waste: [TestCards.make(.diamonds, .seven)]
        )
        XCTAssertTrue(
            HintAdvisor.anyPlayerMoveExists(in: withStock),
            "A flip is a legal action while stock remains"
        )

        let deadBoard = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )
        XCTAssertFalse(
            HintAdvisor.anyPlayerMoveExists(in: deadBoard),
            "Empty stock and no adjacent play: nothing is legal"
        )
    }
}
