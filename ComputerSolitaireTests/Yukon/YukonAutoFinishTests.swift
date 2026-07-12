import XCTest
@testable import Computer_Solitaire

@MainActor
final class YukonAutoFinishTests: XCTestCase {
    func testCandidateRequiresEveryTableauCardFaceUp() {
        var state = almostWonYukonBoard()
        XCTAssertTrue(AutoFinishPlanner.canAutoFinish(in: state))

        state.tableau[0][0].isFaceUp = false
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testScrambledAllFaceUpBoardIsNotAutoFinishable() {
        // Zero face-down cards qualifies the board as a candidate, but the greedy
        // foundation simulation must reject it: the A♠ is buried under its own king,
        // so pure foundation play stalls immediately.
        var foundations = Array(repeating: [Card](), count: 4)
        for (index, suit) in [Suit.hearts, .diamonds, .clubs].enumerated() {
            foundations[index] = Rank.allCases.map { TestCards.make(suit, $0) }
        }
        let spadesRunTopDown = Rank.allCases
            .filter { $0 != .ace && $0 != .king }
            .sorted { $0.rawValue > $1.rawValue }
            .map { TestCards.make(.spades, $0) }
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: foundations,
            tableau: [
                [TestCards.make(.spades, .ace), TestCards.make(.spades, .king)],
                spadesRunTopDown,
                [], [], [], [], []
            ]
        )

        XCTAssertNil(AutoFinishPlanner.nextAutoFinishMove(in: state))
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testAutoFinishPlaysAFinishableBoardToWin() {
        var state = almostWonYukonBoard()
        var steps = 0

        while !state.isWon {
            guard let move = AutoFinishPlanner.nextAutoFinishMove(in: state) else {
                return XCTFail("Auto-finish stalled after \(steps) steps")
            }
            guard let next = AutoMoveAdvisor.simulatedState(
                afterMoving: move.selection,
                to: move.destination,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            ) else {
                return XCTFail("Auto-finish produced an illegal move")
            }
            state = next
            steps += 1
            if steps > 60 {
                return XCTFail("Auto-finish did not converge")
            }
        }
    }

    /// Foundations built through the queens, four kings left on the tableau.
    private func almostWonYukonBoard() -> GameState {
        var state = GameStateFixtures.almostWonForAutoFinish()
        state.variant = .yukon
        return state
    }
}
