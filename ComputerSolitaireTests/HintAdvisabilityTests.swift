import XCTest
@testable import Computer_Solitaire

@MainActor
final class HintAdvisabilityTests: XCTestCase {
    func testAceOnTwoRollbackIsNotAdvisableWithoutNewOpportunity() {
        let aceSpades = makeCard(.spades, .ace, isFaceUp: true)
        let twoHearts = makeCard(.hearts, .two, isFaceUp: true)

        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[aceSpades], [], [], []],
            tableau: [[twoHearts], [], [], [], [], [], []]
        )
        let selection = Selection(source: .foundation(pile: 0), cards: [aceSpades])

        XCTAssertNil(
            AutoMoveAdvisor.bestAdvisableDestination(
                for: selection,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            )
        )
    }

    func testFoundationRollbackIsAdvisableWhenItUnlocksImmediateReveal() {
        let aceSpades = makeCard(.spades, .ace, isFaceUp: true)
        let twoSpades = makeCard(.spades, .two, isFaceUp: true)
        let threeSpades = makeCard(.spades, .three, isFaceUp: true)
        let fourSpades = makeCard(.spades, .four, isFaceUp: true)
        let fiveSpades = makeCard(.spades, .five, isFaceUp: true)
        let sixSpades = makeCard(.spades, .six, isFaceUp: true)
        let sevenHearts = makeCard(.hearts, .seven, isFaceUp: true)
        let kingClubsFaceDown = makeCard(.clubs, .king, isFaceUp: false)
        let fiveDiamonds = makeCard(.diamonds, .five, isFaceUp: true)

        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[aceSpades, twoSpades, threeSpades, fourSpades, fiveSpades, sixSpades], [], [], []],
            tableau: [[sevenHearts], [kingClubsFaceDown, fiveDiamonds], [], [], [], [], []]
        )
        let selection = Selection(source: .foundation(pile: 0), cards: [sixSpades])

        XCTAssertEqual(
            AutoMoveAdvisor.bestAdvisableDestination(
                for: selection,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            ),
            .tableau(0)
        )
    }

    func testUnrelatedExistingRevealDoesNotJustifyFoundationRollback() {
        let aceSpades = makeCard(.spades, .ace, isFaceUp: true)
        let twoHearts = makeCard(.hearts, .two, isFaceUp: true)
        let queenSpadesFaceDown = makeCard(.spades, .queen, isFaceUp: false)
        let nineClubs = makeCard(.clubs, .nine, isFaceUp: true)
        let tenDiamonds = makeCard(.diamonds, .ten, isFaceUp: true)

        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[aceSpades], [], [], []],
            tableau: [[twoHearts], [queenSpadesFaceDown, nineClubs], [tenDiamonds], [], [], [], []]
        )
        let selection = Selection(source: .foundation(pile: 0), cards: [aceSpades])

        XCTAssertNil(
            AutoMoveAdvisor.bestAdvisableDestination(
                for: selection,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            )
        )
    }

    func testBestHintMoveSelectionIsDeterministicAcrossCalls() {
        let fiveHearts = makeCard(.hearts, .five, isFaceUp: true)
        let sixClubs = makeCard(.clubs, .six, isFaceUp: true)
        let sixSpades = makeCard(.spades, .six, isFaceUp: true)

        let state = GameState(
            stock: [],
            waste: [fiveHearts],
            wasteDrawCount: 1,
            foundations: [[], [], [], []],
            tableau: [[sixClubs], [sixSpades], [], [], [], [], []]
        )
        let stockDrawCount = DrawMode.three.rawValue

        let first = HintAdvisor.bestHintMove(in: state, stockDrawCount: stockDrawCount)
        XCTAssertNotNil(first)
        for _ in 0..<20 {
            XCTAssertEqual(HintAdvisor.bestHintMove(in: state, stockDrawCount: stockDrawCount), first)
        }
    }

    func testHintEvaluationPerformanceSmokeTest() {
        let aceSpades = makeCard(.spades, .ace, isFaceUp: true)
        let twoSpades = makeCard(.spades, .two, isFaceUp: true)
        let threeSpades = makeCard(.spades, .three, isFaceUp: true)
        let fourSpades = makeCard(.spades, .four, isFaceUp: true)
        let fiveSpades = makeCard(.spades, .five, isFaceUp: true)
        let sixSpades = makeCard(.spades, .six, isFaceUp: true)
        let sevenHearts = makeCard(.hearts, .seven, isFaceUp: true)
        let queenClubsFaceDown = makeCard(.clubs, .queen, isFaceUp: false)
        let jackDiamonds = makeCard(.diamonds, .jack, isFaceUp: true)
        let tenClubs = makeCard(.clubs, .ten, isFaceUp: true)
        let nineHearts = makeCard(.hearts, .nine, isFaceUp: true)

        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[aceSpades, twoSpades, threeSpades, fourSpades, fiveSpades, sixSpades], [], [], []],
            tableau: [
                [sevenHearts],
                [queenClubsFaceDown, jackDiamonds, tenClubs, nineHearts],
                [],
                [],
                [],
                [],
                []
            ]
        )

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<400 {
            _ = HintAdvisor.bestHint(in: state, stockDrawCount: DrawMode.three.rawValue)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Wide threshold to catch pathological regressions without being flaky.
        XCTAssertLessThan(elapsed, 3.0)
    }

    private func makeCard(_ suit: Suit, _ rank: Rank, isFaceUp: Bool) -> Card {
        Card(suit: suit, rank: rank, isFaceUp: isFaceUp)
    }
}
