import XCTest
@testable import Computer_Solitaire

@MainActor
final class HintAdvisorCoverageTests: XCTestCase {
    func testBestHintPrefersMoveWhenAvailable() {
        let aceSpades = TestCards.make(.spades, .ace, isFaceUp: true)
        let state = GameState(
            stock: [],
            waste: [aceSpades],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7)
        )

        let hint = HintAdvisor.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue)
        guard case .move(let move)? = hint else {
            return XCTFail("Expected move hint")
        }
        XCTAssertEqual(move.selection.source, .waste)
        XCTAssertEqual(move.destination, .foundation(0))
    }

    func testBestHintReturnsStockTapWhenFutureMoveAppearsAfterDraw() {
        let fiveHearts = TestCards.make(.hearts, .five, isFaceUp: false)
        let sixClubs = TestCards.make(.clubs, .six, isFaceUp: true)
        let state = GameState(
            stock: [fiveHearts],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[sixClubs], [], [], [], [], [], []]
        )

        let hint = HintAdvisor.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue)
        XCTAssertEqual(hint, .stockTap)
    }

    func testBestHintReturnsNilWhenNoMoveAndNoStockCycle() {
        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[TestCards.make(.clubs, .six, isFaceUp: true)], [], [], [], [], [], []]
        )
        XCTAssertNil(HintAdvisor.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue))
    }
}
