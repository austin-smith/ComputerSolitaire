import XCTest
@testable import Computer_Solitaire

@MainActor
final class AutoFinishPlannerTests: XCTestCase {
    func testCanAutoFinishRejectsNonCandidateStates() {
        var state = GameStateFixtures.almostWonForAutoFinish()
        state.stock = [TestCards.make(.spades, .ace, isFaceUp: false)]
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))

        state = GameStateFixtures.almostWonForAutoFinish()
        state.stock = []
        state.waste = [TestCards.make(.spades, .ace, isFaceUp: true)]
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))

        state = GameStateFixtures.almostWonForAutoFinish()
        state.tableau[0][0].isFaceUp = false
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testNextAutoFinishMoveReturnsDeterministicFirstMove() {
        let state = GameStateFixtures.almostWonForAutoFinish()

        let move = AutoFinishPlanner.nextAutoFinishMove(in: state)
        XCTAssertNotNil(move)
        XCTAssertEqual(move?.destination, .foundation(0))

        if case .tableau(let pile, let index) = move?.selection.source {
            XCTAssertEqual(pile, 0)
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Expected tableau source")
        }
    }

    func testCanAutoFinishSucceedsForSimpleAlmostWonBoard() {
        XCTAssertTrue(AutoFinishPlanner.canAutoFinish(in: GameStateFixtures.almostWonForAutoFinish()))
    }

    func testCanAutoFinishReturnsFalseWhenNoProgressMoveExists() {
        var foundations = Array(repeating: [Card](), count: 4)
        foundations[0] = Rank.allCases
            .filter { $0 != .king }
            .map { TestCards.make(.spades, $0, isFaceUp: true) }

        // King of hearts cannot go to any foundation here.
        let blocked = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: foundations,
            tableau: [[TestCards.make(.hearts, .king, isFaceUp: true)], [], [], [], [], [], []]
        )

        XCTAssertNil(AutoFinishPlanner.nextAutoFinishMove(in: blocked))
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: blocked))
    }
}
