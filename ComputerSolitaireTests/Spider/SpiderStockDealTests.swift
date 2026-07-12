import XCTest
@testable import Computer_Solitaire

@MainActor
final class SpiderStockDealTests: XCTestCase {
    func testDealPlacesOneFaceUpCardOnEveryPileInOrder() {
        let stock = (1...20).map { _ in TestCards.make(.spades, .two, isFaceUp: false) }
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.fullBoard(topRank: .five, stock: stock)
        viewModel.configureSpiderNewGame()
        // The last ten stock cards land on piles 0-9, in order.
        let expectedDealtIDs = viewModel.state.stock.suffix(10).map(\.id)

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.stock.count, 10)
        XCTAssertEqual(viewModel.state.tableau.map(\.count), Array(repeating: 2, count: 10))
        let dealtByPile = viewModel.state.tableau.map { pile in pile[1] }
        XCTAssertEqual(dealtByPile.map(\.id), expectedDealtIDs.reversed())
        XCTAssertTrue(dealtByPile.allSatisfy(\.isFaceUp))
        XCTAssertEqual(viewModel.movesCount, 1, "A deal is one move")
    }

    func testDealIsBlockedWhileAnyPileIsEmpty() {
        let stock = (1...10).map { _ in TestCards.make(.spades, .two, isFaceUp: false) }
        let viewModel = SolitaireViewModel()
        var board = SpiderTestStates.fullBoard(topRank: .five, stock: stock)
        board.tableau[3] = []
        viewModel.state = board
        viewModel.configureSpiderNewGame()
        let stateBeforeTap = viewModel.state

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state, stateBeforeTap, "A blocked deal must not change the board")
        XCTAssertEqual(viewModel.movesCount, 0)
        XCTAssertFalse(viewModel.canUndo, "A blocked deal must not push an undo snapshot")
    }

    func testFiveDealsExhaustTheStockAndAFurtherTapIsANoOp() {
        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededSpiderDeal(seed: 1, suitCount: .two)
        viewModel.configureSpiderNewGame()

        for expectedRemaining in [40, 30, 20, 10, 0] {
            viewModel.handleStockTap()
            XCTAssertEqual(viewModel.state.stock.count, expectedRemaining)
        }
        XCTAssertEqual(viewModel.movesCount, 5)
        XCTAssertEqual(
            viewModel.state.tableau.reduce(0) { $0 + $1.count }
                + viewModel.state.foundations.reduce(0) { $0 + $1.count },
            104
        )

        let stateAfterFiveDeals = viewModel.state
        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.state, stateAfterFiveDeals, "An empty stock tap is a no-op")
        XCTAssertEqual(viewModel.movesCount, 5)
    }

    func testSingleUndoRestoresTheWholeDealtRow() {
        let viewModel = SolitaireViewModel()
        viewModel.state = GameStateFixtures.seededSpiderDeal(seed: 2, suitCount: .four)
        viewModel.configureSpiderNewGame()
        let stateBeforeDeal = viewModel.state
        let scoreBeforeDeal = viewModel.score

        viewModel.handleStockTap()
        XCTAssertNotEqual(viewModel.state, stateBeforeDeal)
        XCTAssertEqual(
            viewModel.peekUndoSnapshot()?.undoContext?.action,
            .dealTableauRow
        )

        viewModel.undo()
        XCTAssertEqual(viewModel.state, stateBeforeDeal, "One undo must restore all ten dealt cards")
        XCTAssertEqual(viewModel.score, scoreBeforeDeal)
        XCTAssertEqual(viewModel.movesCount, 0)
    }
}
