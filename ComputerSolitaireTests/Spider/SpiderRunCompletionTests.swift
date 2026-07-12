import XCTest
@testable import Computer_Solitaire

@MainActor
final class SpiderRunCompletionTests: XCTestCase {
    /// King through Two of one suit, face up — one Ace short of a full run.
    private func kingThroughTwo(_ suit: Suit) -> [Card] {
        Rank.allCases.reversed().dropLast().map { TestCards.make(suit, $0) }
    }

    func testMoveCompletedRunIsBankedToTheFirstEmptyFoundation() {
        let aceSpades = TestCards.make(.spades, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [kingThroughTwo(.spades), [aceSpades], [TestCards.make(.hearts, .four)]]
        )
        viewModel.configureSpiderNewGame()
        let scoreBeforeMove = viewModel.score

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceSpades])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertTrue(viewModel.state.tableau[0].isEmpty, "The completed run leaves the tableau")
        let bankedRun = viewModel.state.foundations[0]
        XCTAssertEqual(bankedRun.count, 13)
        XCTAssertEqual(bankedRun.first?.rank, .ace, "Banked runs stack Ace at the bottom")
        XCTAssertEqual(bankedRun.last?.rank, .king)
        XCTAssertTrue(bankedRun.allSatisfy { $0.suit == .spades })
        XCTAssertEqual(
            viewModel.score,
            scoreBeforeMove + Scoring.delta(for: .spiderMove) + Scoring.delta(for: .spiderCompletedRun)
        )
        XCTAssertFalse(viewModel.isWin)
    }

    func testDealCompletedRunIsBankedAndExposedCardFlips() {
        // Pile 0 holds a hidden card under K→2 of spades; the deal drops A♠
        // onto it (the stock's last card lands on pile 0).
        let hiddenCard = TestCards.make(.hearts, .nine, isFaceUp: false)
        var board = SpiderTestStates.fullBoard(topRank: .five)
        board.tableau[0] = [hiddenCard] + kingThroughTwo(.spades)
        var stock = (1...9).map { _ in TestCards.make(.hearts, .two, isFaceUp: false) }
        stock.append(TestCards.make(.spades, .ace, isFaceUp: false))
        board.stock = stock

        let viewModel = SolitaireViewModel()
        viewModel.state = board
        viewModel.configureSpiderNewGame()
        let scoreBeforeDeal = viewModel.score

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.foundations[0].count, 13)
        XCTAssertEqual(viewModel.state.tableau[0].count, 1)
        XCTAssertEqual(viewModel.state.tableau[0][0].id, hiddenCard.id)
        XCTAssertTrue(
            viewModel.state.tableau[0][0].isFaceUp,
            "The card the banked run exposed should flip"
        )
        XCTAssertEqual(
            viewModel.score,
            scoreBeforeDeal + Scoring.delta(for: .spiderMove) + Scoring.delta(for: .spiderCompletedRun)
        )
    }

    func testExposedFlipAfterCompletionScoresNothing() {
        // Spider's classic scheme has no reveal bonus: banking a run over a
        // face-down card changes the score by the move and the run only.
        let hiddenCard = TestCards.make(.hearts, .nine, isFaceUp: false)
        let aceSpades = TestCards.make(.spades, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [[hiddenCard] + kingThroughTwo(.spades), [aceSpades]]
        )
        viewModel.configureSpiderNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceSpades])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertTrue(viewModel.state.tableau[0][0].isFaceUp)
        XCTAssertEqual(
            viewModel.score,
            Scoring.spiderInitialScore
                + Scoring.delta(for: .spiderMove)
                + Scoring.delta(for: .spiderCompletedRun),
            "The exposed flip must not add the Klondike-family reveal bonus"
        )
    }

    func testOneRemovalCanExposeAndBankASecondCompleteRun() {
        // A full heart run sits under K→2 of spades; landing the A♠ banks the
        // spade run, exposing the complete heart run, which banks too.
        let heartRun = Rank.allCases.reversed().map { TestCards.make(.hearts, $0) }
        let aceSpades = TestCards.make(.spades, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [heartRun + kingThroughTwo(.spades), [aceSpades]]
        )
        viewModel.configureSpiderNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceSpades])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertTrue(viewModel.state.tableau[0].isEmpty)
        XCTAssertEqual(viewModel.state.foundations[0].count, 13)
        XCTAssertEqual(viewModel.state.foundations[1].count, 13)
        XCTAssertEqual(
            viewModel.score,
            Scoring.spiderInitialScore
                + Scoring.delta(for: .spiderMove)
                + Scoring.delta(for: .spiderCompletedRun) * 2
        )
    }

    func testDealCanCompleteTwoRunsAtOnce() {
        var board = SpiderTestStates.fullBoard(topRank: .five)
        board.tableau[0] = kingThroughTwo(.spades)
        board.tableau[1] = kingThroughTwo(.hearts)
        // Pile 0 takes the stock's last card, pile 1 the one before it.
        var stock = (1...8).map { _ in TestCards.make(.clubs, .two, isFaceUp: false) }
        stock.append(TestCards.make(.hearts, .ace, isFaceUp: false))
        stock.append(TestCards.make(.spades, .ace, isFaceUp: false))
        board.stock = stock

        let viewModel = SolitaireViewModel()
        viewModel.state = board
        viewModel.configureSpiderNewGame()

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.foundations[0].count, 13)
        XCTAssertEqual(viewModel.state.foundations[1].count, 13)
        XCTAssertTrue(viewModel.state.tableau[0].isEmpty)
        XCTAssertTrue(viewModel.state.tableau[1].isEmpty)
    }

    func testEighthCompletedRunWinsTheGame() {
        var foundations: [[Card]] = (0..<7).map { _ in
            Rank.allCases.map { TestCards.make(.spades, $0) }
        }
        foundations.append([])
        let aceHearts = TestCards.make(.hearts, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [kingThroughTwo(.hearts), [aceHearts]],
            foundations: foundations
        )
        viewModel.configureSpiderNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceHearts])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertTrue(viewModel.state.isWon)
        XCTAssertTrue(viewModel.isWin)
        XCTAssertNotNil(viewModel.finalElapsedSeconds, "A win must finalize the clock")
    }

    func testSingleUndoRestoresACompletedRun() {
        let aceSpades = TestCards.make(.spades, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [kingThroughTwo(.spades), [aceSpades], [TestCards.make(.hearts, .four)]]
        )
        viewModel.configureSpiderNewGame()
        let stateBeforeMove = viewModel.state
        let scoreBeforeMove = viewModel.score

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceSpades])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))
        XCTAssertEqual(viewModel.state.foundations[0].count, 13)

        viewModel.undo()
        XCTAssertEqual(
            viewModel.state,
            stateBeforeMove,
            "One undo must restore the run to the tableau and the Ace to its pile"
        )
        XCTAssertEqual(viewModel.score, scoreBeforeMove)
    }
}
