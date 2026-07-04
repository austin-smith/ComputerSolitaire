import XCTest
@testable import Computer_Solitaire

@MainActor
final class FreeCellSolverTests: XCTestCase {
    /// Statistical coverage (solve rate across random deals) was established with the
    /// release-build probe study; these fixed deals are regression guards, so a failure
    /// is reproducible instead of depending on whatever CI happens to shuffle.
    private static let solvableDealSeeds: [UInt64] = Array(1...20)

    /// Every returned solution must replay legally through the app's own move engine
    /// to a won board.
    func testSolvesFixedDealsAndSolutionsReplayLegally() {
        for seed in Self.solvableDealSeeds {
            let state = GameStateFixtures.seededFreeCellDeal(seed: seed)
            guard let solution = FreeCellSolver.solve(
                state,
                limits: FreeCellSolver.Limits(deadline: Date().addingTimeInterval(10.0))
            ) else {
                return XCTFail("Seeded deal \(seed) should solve within budget")
            }

            var replay = state
            for move in solution.moves {
                guard let (selection, destination) = FreeCellSolver.materialize(move, in: replay),
                      let next = AutoMoveAdvisor.simulatedState(
                        afterMoving: selection,
                        to: destination,
                        in: replay,
                        stockDrawCount: DrawMode.three.rawValue
                      ) else {
                    return XCTFail("Seed \(seed): solution contained a move that is illegal in the app model")
                }
                replay = next
            }
            XCTAssertTrue(
                replay.foundations.allSatisfy { $0.count == Rank.allCases.count },
                "Seed \(seed): replaying the solution must win the game"
            )
        }
    }

    func testKeyedMovesFollowTheSolutionLine() throws {
        let state = GameStateFixtures.seededFreeCellDeal(seed: 42)
        guard let solution = FreeCellSolver.solve(
            state,
            limits: FreeCellSolver.Limits(deadline: Date().addingTimeInterval(10.0))
        ) else {
            return XCTFail("Seeded deal should solve within budget")
        }

        let plan = FreeCellSolver.keyedMoves(along: solution, from: state)
        XCTAssertEqual(plan.count, solution.moves.count)

        var replay = state
        for expectedMove in solution.moves {
            let key = FreeCellSolver.stateKey(for: replay)
            XCTAssertEqual(plan[key], expectedMove)
            guard let (selection, destination) = FreeCellSolver.materialize(expectedMove, in: replay),
                  let next = AutoMoveAdvisor.simulatedState(
                    afterMoving: selection,
                    to: destination,
                    in: replay,
                    stockDrawCount: DrawMode.three.rawValue
                  ) else {
                return XCTFail("Plan replay broke")
            }
            replay = next
        }
    }

    func testHintPlannerWinsAFreshDealEndToEnd() {
        let planner = HintPlanner()
        var state = GameStateFixtures.seededFreeCellDeal(seed: 7)
        var steps = 0
        while steps < 400 {
            steps += 1
            if state.foundations.allSatisfy({ $0.count == Rank.allCases.count }) {
                return
            }
            guard let hint = planner.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue),
                  case .move(let move) = hint,
                  let next = AutoMoveAdvisor.simulatedState(
                    afterMoving: move.selection,
                    to: move.destination,
                    in: state,
                    stockDrawCount: DrawMode.three.rawValue
                  ) else {
                return XCTFail("Hint chain broke after \(steps) steps")
            }
            state = next
        }
        XCTFail("Did not win within 400 hint-followed moves")
    }

    func testMaterializeRoutesFoundationMovesToMatchingSuitPile() {
        let aceHearts = TestCards.make(.hearts, .ace)
        let state = GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: [nil, nil, nil, nil],
            foundations: [[TestCards.make(.spades, .ace)], [], [], []],
            tableau: [[aceHearts], [], [], [], [], [], [], []]
        )

        let move = FreeCellSolver.Move(source: .cascade(pile: 0, count: 1), target: .foundation)
        let materialized = FreeCellSolver.materialize(move, in: state)
        XCTAssertEqual(materialized?.destination, .foundation(1), "Ace must open a fresh foundation pile")
        XCTAssertEqual(materialized?.selection.cards.first?.id, aceHearts.id)
    }
}
