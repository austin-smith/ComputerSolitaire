import XCTest
@testable import Computer_Solitaire

@MainActor
final class SpiderScoringTests: XCTestCase {
    func testNewGameStartsAtTheClassicInitialScore() {
        let viewModel = SolitaireViewModel()
        viewModel.newGame(variant: .spider)
        XCTAssertEqual(viewModel.score, Scoring.spiderInitialScore)

        viewModel.redeal()
        XCTAssertEqual(viewModel.score, Scoring.spiderInitialScore, "A redeal restarts the balance")
    }

    func testEveryTableauMoveCostsOnePoint() {
        let fiveHearts = TestCards.make(.hearts, .five)
        let sixSpades = TestCards.make(.spades, .six)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(tableau: [[fiveHearts], [sixSpades]])
        viewModel.configureSpiderNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 0, index: 0), cards: [fiveHearts])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))

        XCTAssertEqual(viewModel.score, Scoring.spiderInitialScore - 1)
    }

    func testStockDealCostsOnePoint() {
        let stock = (1...10).map { _ in TestCards.make(.hearts, .two, isFaceUp: false) }
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.fullBoard(topRank: .five, stock: stock)
        viewModel.configureSpiderNewGame()

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.score, Scoring.spiderInitialScore - 1)
    }

    func testScoreIsClampedAtZero() {
        let fiveHearts = TestCards.make(.hearts, .five)
        let sixSpades = TestCards.make(.spades, .six)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(tableau: [[fiveHearts], [sixSpades]])
        viewModel.configureSpiderNewGame()
        viewModel.setInitialScore(0)

        viewModel.selection = Selection(source: .tableau(pile: 0, index: 0), cards: [fiveHearts])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))

        XCTAssertEqual(viewModel.score, 0)
    }

    func testWinAddsTheStandardTimeBonus() {
        // Seven runs banked; the final Ace completes the eighth. The provider
        // pins the clock, so the expected bonus is exact.
        var foundations: [[Card]] = (0..<7).map { _ in
            Rank.allCases.map { TestCards.make(.spades, $0) }
        }
        foundations.append([])
        let kingThroughTwoHearts = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.hearts, $0) }
        let aceHearts = TestCards.make(.hearts, .ace)

        let dateProvider = TestDateProvider(now: DateFixtures.reference)
        let viewModel = SolitaireViewModel(dateProvider: dateProvider)
        viewModel.state = SpiderTestStates.board(
            tableau: [Array(kingThroughTwoHearts), [aceHearts]],
            foundations: foundations
        )
        viewModel.configureSpiderNewGame()
        let scoreBeforeWin = viewModel.score

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
            scoreBeforeWin
                + Scoring.delta(for: .spiderMove)
                + Scoring.delta(for: .spiderCompletedRun)
                + expectedBonus
        )
    }
}
