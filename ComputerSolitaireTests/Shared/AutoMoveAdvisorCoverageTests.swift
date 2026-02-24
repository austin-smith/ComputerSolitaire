import XCTest
@testable import Computer_Solitaire

@MainActor
final class AutoMoveAdvisorCoverageTests: XCTestCase {
    func testCandidateSelectionsIncludesWasteFoundationAndValidTableauRuns() {
        let wasteCard = TestCards.make(.spades, .ace, isFaceUp: true)
        let foundationCard = TestCards.make(.hearts, .ace, isFaceUp: true)
        let tableauRun = [
            TestCards.make(.clubs, .seven, isFaceUp: true),
            TestCards.make(.hearts, .six, isFaceUp: true),
            TestCards.make(.clubs, .five, isFaceUp: true)
        ]
        let state = GameState(
            stock: [],
            waste: [wasteCard],
            wasteDrawCount: 1,
            foundations: [[foundationCard], [], [], []],
            tableau: [tableauRun, [], [], [], [], [], []]
        )

        let selections = AutoMoveAdvisor.candidateSelections(in: state)
        XCTAssertTrue(selections.contains(where: { $0.source == .waste }))
        XCTAssertTrue(selections.contains(where: { $0.source == .foundation(pile: 0) }))
        XCTAssertTrue(
            selections.contains(
                where: {
                    if case .tableau(let pile, let index) = $0.source {
                        return pile == 0 && index == 0
                    }
                    return false
                }
            )
        )
    }

    func testLegalDestinationsRejectsRedundantKingTransferBetweenEmptyColumns() {
        let kingSpades = TestCards.make(.spades, .king, isFaceUp: true)
        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[kingSpades], [], [], [], [], [], []]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: [kingSpades])

        let destinations = AutoMoveAdvisor.legalDestinations(for: selection, in: state)
        XCTAssertFalse(destinations.contains(.tableau(1)))
    }

    func testBestDestinationMovesWasteAceToFoundation() {
        let aceSpades = TestCards.make(.spades, .ace, isFaceUp: true)
        let state = GameState(
            stock: [],
            waste: [aceSpades],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: Array(repeating: [], count: 7)
        )
        let selection = Selection(source: .waste, cards: [aceSpades])

        XCTAssertEqual(
            AutoMoveAdvisor.bestDestination(
                for: selection,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            ),
            .foundation(0)
        )
    }

    func testBestAdvisableDestinationRejectsFoundationToFoundationAndNonMatchingSelections() {
        let aceSpades = TestCards.make(.spades, .ace, isFaceUp: true)
        let twoSpades = TestCards.make(.spades, .two, isFaceUp: true)
        let state = GameState(
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[aceSpades], [twoSpades], [], []],
            tableau: Array(repeating: [], count: 7)
        )
        let badSelection = Selection(source: .foundation(pile: 0), cards: [twoSpades])

        XCTAssertNil(
            AutoMoveAdvisor.bestAdvisableDestination(
                for: badSelection,
                in: state,
                stockDrawCount: DrawMode.three.rawValue
            )
        )
    }

    func testBestMoveEvaluationProvidesPositiveMobilityForUsefulMove() {
        let sixClubs = TestCards.make(.clubs, .six, isFaceUp: true)
        let fiveHearts = TestCards.make(.hearts, .five, isFaceUp: true)
        let state = GameState(
            stock: [],
            waste: [fiveHearts],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: [[sixClubs], [], [], [], [], [], []]
        )
        let selection = Selection(source: .waste, cards: [fiveHearts])

        let evaluation = AutoMoveAdvisor.bestMoveEvaluation(
            for: selection,
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        )
        XCTAssertNotNil(evaluation)
        XCTAssertEqual(evaluation?.destination, .tableau(0))
        XCTAssertGreaterThanOrEqual(evaluation?.resultingMobility ?? -1, 0)
    }
}
