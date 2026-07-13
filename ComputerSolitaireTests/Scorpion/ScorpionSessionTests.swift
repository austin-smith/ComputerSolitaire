import XCTest
@testable import Computer_Solitaire

@MainActor
final class ScorpionSessionTests: XCTestCase {
    // MARK: - Stock deal

    func testStockTapDealsAnytimeIncludingOntoAnEmptyPile() {
        let viewModel = SolitaireViewModel()
        var board = GameStateFixtures.seededScorpionDeal(seed: 7)
        board.tableau[0] = []
        viewModel.state = board
        viewModel.configureWastelessNewGame()
        // The stock deals from its end: its last card lands on pile 0 first.
        let expectedDealtIDs = Array(viewModel.state.stock.map(\.id).reversed())

        viewModel.handleStockTap()

        XCTAssertTrue(viewModel.state.stock.isEmpty)
        let dealtByPile = (0..<3).map { viewModel.state.tableau[$0].last! }
        XCTAssertEqual(dealtByPile.map(\.id), expectedDealtIDs)
        XCTAssertTrue(dealtByPile.allSatisfy(\.isFaceUp))
        XCTAssertEqual(
            viewModel.state.tableau[0].count,
            1,
            "The deal lands on an empty pile too — mid-run and empty piles never block it"
        )
        XCTAssertEqual(viewModel.movesCount, 1, "A deal is one move")
    }

    func testEmptyStockTapIsANoOp() {
        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededScorpionDeal(seed: 7)
        viewModel.configureWastelessNewGame()

        viewModel.handleStockTap()
        XCTAssertTrue(viewModel.state.stock.isEmpty)
        let stateAfterDeal = viewModel.state

        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.state, stateAfterDeal, "An empty stock tap is a no-op")
        XCTAssertEqual(viewModel.movesCount, 1)
        XCTAssertFalse(viewModel.canInteractWithStock)
    }

    func testSingleUndoRestoresTheWholeDeal() {
        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededScorpionDeal(seed: 8)
        viewModel.configureWastelessNewGame()
        let stateBeforeDeal = viewModel.state
        let scoreBeforeDeal = viewModel.score

        viewModel.handleStockTap()
        XCTAssertNotEqual(viewModel.state, stateBeforeDeal)
        XCTAssertEqual(
            viewModel.peekUndoSnapshot()?.undoContext?.action,
            .dealTableauRow
        )

        viewModel.undo()
        XCTAssertEqual(viewModel.state, stateBeforeDeal, "One undo must restore all three dealt cards")
        XCTAssertEqual(viewModel.score, scoreBeforeDeal)
        XCTAssertEqual(viewModel.movesCount, 0)
    }

    // MARK: - Scoring

    func testTableauMovesAreFreeAndRevealsScore() {
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let nineSpades = TestCards.make(.spades, .nine)
        let tenSpades = TestCards.make(.spades, .ten)
        let eightSpades = TestCards.make(.spades, .eight)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(
            tableau: [[hiddenKing, nineSpades], [tenSpades], [eightSpades]]
        )
        viewModel.configureWastelessNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 0, index: 1), cards: [nineSpades])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))

        XCTAssertEqual(
            viewModel.score,
            Scoring.delta(for: .turnOverTableauCard),
            "The move itself is free; the flip it exposes scores"
        )

        viewModel.selection = Selection(source: .tableau(pile: 2, index: 0), cards: [eightSpades])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))
        XCTAssertEqual(
            viewModel.score,
            Scoring.delta(for: .turnOverTableauCard),
            "A move that reveals nothing scores nothing"
        )
    }

    func testBankingARunScores() {
        let heartRunToTwo = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.hearts, $0) }
        let aceHearts = TestCards.make(.hearts, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(
            tableau: [Array(heartRunToTwo), [aceHearts]]
        )
        viewModel.configureWastelessNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceHearts])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertEqual(viewModel.state.foundations[0].count, 13)
        XCTAssertTrue(viewModel.state.tableau[0].isEmpty)
        XCTAssertEqual(viewModel.score, Scoring.delta(for: .scorpionCompletedRun))
    }

    func testBankingARunOverAFaceDownCardScoresTheRevealToo() {
        // The banked run's removal turns the buried card face up; that reveal
        // earns the same +5 as any other, alongside the run's +100.
        let hiddenCard = TestCards.make(.clubs, .four, isFaceUp: false)
        let heartRunToTwo = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.hearts, $0) }
        let aceHearts = TestCards.make(.hearts, .ace)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(
            tableau: [[hiddenCard] + heartRunToTwo, [aceHearts]]
        )
        viewModel.configureWastelessNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceHearts])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertEqual(viewModel.state.foundations[0].count, 13)
        XCTAssertTrue(viewModel.state.tableau[0][0].isFaceUp)
        XCTAssertEqual(
            viewModel.score,
            Scoring.delta(for: .scorpionCompletedRun) + Scoring.delta(for: .turnOverTableauCard)
        )
    }

    func testWinAddsTheStandardTimeBonus() {
        // Three runs banked; the final Ace completes the fourth. The provider
        // pins the clock, so the expected bonus is exact.
        var foundations: [[Card]] = [Suit.spades, .clubs, .diamonds].map { suit in
            Rank.allCases.map { TestCards.make(suit, $0) }
        }
        foundations.append([])
        let heartRunToTwo = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.hearts, $0) }
        let aceHearts = TestCards.make(.hearts, .ace)

        let dateProvider = TestDateProvider(now: DateFixtures.reference)
        let viewModel = SolitaireViewModel(dateProvider: dateProvider)
        viewModel.state = ScorpionTestStates.board(
            tableau: [Array(heartRunToTwo), [aceHearts]],
            foundations: foundations
        )
        viewModel.configureWastelessNewGame()

        dateProvider.now = DateFixtures.plus(60)
        viewModel.selection = Selection(source: .tableau(pile: 1, index: 0), cards: [aceHearts])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertTrue(viewModel.isWin)
        let expectedBonus = Scoring.timeBonus(
            elapsedSeconds: 60,
            maxBonus: Scoring.timedMaxBonus(for: DrawMode.three.rawValue)
        )
        XCTAssertGreaterThan(expectedBonus, 0)
        XCTAssertEqual(
            viewModel.score,
            Scoring.delta(for: .scorpionCompletedRun) + expectedBonus
        )
    }

    // MARK: - Selection and interaction

    func testExposedFaceDownTopFlipsOnTapAndScores() {
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(tableau: [[hiddenKing]])
        viewModel.configureWastelessNewGame()

        viewModel.handleTableauTap(pileIndex: 0, cardIndex: 0)

        XCTAssertTrue(viewModel.state.tableau[0][0].isFaceUp)
        XCTAssertEqual(viewModel.score, Scoring.delta(for: .turnOverTableauCard))
        XCTAssertEqual(viewModel.movesCount, 1)
    }

    func testDragFromAnyFaceUpCardStartsAnUnorderedSelection() {
        let nineSpades = TestCards.make(.spades, .nine)
        let fourHearts = TestCards.make(.hearts, .four)
        let twoClubs = TestCards.make(.clubs, .two)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(
            tableau: [[nineSpades, fourHearts, twoClubs], [TestCards.make(.spades, .ten)]]
        )
        viewModel.configureWastelessNewGame()

        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 0))
        XCTAssertEqual(
            viewModel.selection?.cards.map(\.id),
            [nineSpades.id, fourHearts.id, twoClubs.id]
        )
    }
}
