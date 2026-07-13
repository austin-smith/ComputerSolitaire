import XCTest
@testable import Computer_Solitaire

@MainActor
final class GolfRulesTests: XCTestCase {
    // MARK: Adjacency

    func testStrictAdjacencyNeverWraps() {
        XCTAssertTrue(GolfGameRules.ranksAreAdjacent(Rank.ace.rawValue, Rank.two.rawValue))
        XCTAssertTrue(GolfGameRules.ranksAreAdjacent(Rank.queen.rawValue, Rank.king.rawValue))
        XCTAssertFalse(GolfGameRules.ranksAreAdjacent(Rank.king.rawValue, Rank.ace.rawValue))
        XCTAssertFalse(GolfGameRules.ranksAreAdjacent(Rank.ace.rawValue, Rank.king.rawValue))
        XCTAssertFalse(GolfGameRules.ranksAreAdjacent(Rank.five.rawValue, Rank.five.rawValue))
        XCTAssertFalse(GolfGameRules.ranksAreAdjacent(Rank.five.rawValue, Rank.seven.rawValue))
    }

    func testNothingPlaysOnAKingButAKingPlaysOnAQueen() {
        // The dead-end is one-directional: a King may land on a Queen, but a
        // waste-top King accepts nothing — not even a Queen.
        XCTAssertTrue(
            GolfGameRules.canPlayRank(Rank.king.rawValue, ontoWasteTop: Rank.queen.rawValue)
        )
        XCTAssertFalse(
            GolfGameRules.canPlayRank(Rank.queen.rawValue, ontoWasteTop: Rank.king.rawValue)
        )
        XCTAssertFalse(
            GolfGameRules.canPlayRank(Rank.ace.rawValue, ontoWasteTop: Rank.king.rawValue)
        )
    }

    func testAceConnectsOnlyToTwo() {
        XCTAssertTrue(GolfGameRules.canPlayRank(Rank.two.rawValue, ontoWasteTop: Rank.ace.rawValue))
        XCTAssertTrue(GolfGameRules.canPlayRank(Rank.ace.rawValue, ontoWasteTop: Rank.two.rawValue))
        XCTAssertFalse(GolfGameRules.canPlayRank(Rank.king.rawValue, ontoWasteTop: Rank.ace.rawValue))
    }

    // MARK: canPlay

    func testCanPlayRequiresExposedAdjacentCard() {
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.spades, .nine), TestCards.make(.hearts, .seven)],
                [TestCards.make(.clubs, .three)]
            ],
            waste: [TestCards.make(.diamonds, .six)]
        )

        // Column 0's exposed seven is adjacent to the six; the buried nine is not playable.
        XCTAssertTrue(GolfGameRules.canPlay(column: 0, in: state))
        // Column 1's three is not adjacent to the six.
        XCTAssertFalse(GolfGameRules.canPlay(column: 1, in: state))
        // Empty columns and out-of-range indices never play.
        XCTAssertFalse(GolfGameRules.canPlay(column: 2, in: state))
        XCTAssertFalse(GolfGameRules.canPlay(column: 99, in: state))
    }

    func testCanPlayRejectsWasteTopKing() {
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .queen)]],
            waste: [TestCards.make(.diamonds, .king)]
        )
        XCTAssertFalse(GolfGameRules.canPlay(column: 0, in: state))
    }

    func testCanPlayRejectsWrongVariant() {
        var state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .seven)]],
            waste: [TestCards.make(.diamonds, .six)]
        )
        state.variant = .klondike
        XCTAssertFalse(GolfGameRules.canPlay(column: 0, in: state))
    }

    // MARK: stateByApplying

    private func exposedSelection(column: Int, in state: GameState) -> Selection {
        Selection(
            source: .tableau(pile: column, index: state.tableau[column].count - 1),
            cards: [state.tableau[column].last!]
        )
    }

    func testStateByApplyingPlaysExposedCardOntoWaste() {
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.spades, .nine), TestCards.make(.hearts, .seven)],
                [TestCards.make(.clubs, .three)]
            ],
            waste: [TestCards.make(.diamonds, .six)]
        )
        let seven = state.tableau[0].last!

        let nextState = GolfGameRules.stateByApplying(
            selection: exposedSelection(column: 0, in: state),
            destination: .waste,
            to: state
        )

        XCTAssertNotNil(nextState)
        XCTAssertEqual(nextState?.tableau[0].count, 1)
        XCTAssertEqual(nextState?.tableau[0].last?.rank, .nine)
        XCTAssertEqual(nextState?.waste.last?.id, seven.id)
        XCTAssertEqual(nextState?.wasteDrawCount, 1)
    }

    func testStateByApplyingRejectsIllegalMoves() {
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.spades, .nine), TestCards.make(.hearts, .seven)],
                [TestCards.make(.clubs, .three)]
            ],
            waste: [TestCards.make(.diamonds, .six)]
        )

        // Buried card.
        let buriedSelection = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: [state.tableau[0][0]]
        )
        XCTAssertNil(
            GolfGameRules.stateByApplying(selection: buriedSelection, destination: .waste, to: state)
        )

        // Non-adjacent exposed card.
        XCTAssertNil(
            GolfGameRules.stateByApplying(
                selection: exposedSelection(column: 1, in: state),
                destination: .waste,
                to: state
            )
        )

        // Wrong destination.
        XCTAssertNil(
            GolfGameRules.stateByApplying(
                selection: exposedSelection(column: 0, in: state),
                destination: .tableau(1),
                to: state
            )
        )

        // Stale card identity.
        let staleSelection = Selection(
            source: .tableau(pile: 0, index: state.tableau[0].count - 1),
            cards: [TestCards.make(.hearts, .seven)]
        )
        XCTAssertNil(
            GolfGameRules.stateByApplying(selection: staleSelection, destination: .waste, to: state)
        )

        // Wrong variant.
        var klondikeState = state
        klondikeState.variant = .klondike
        XCTAssertNil(
            GolfGameRules.stateByApplying(
                selection: exposedSelection(column: 0, in: klondikeState),
                destination: .waste,
                to: klondikeState
            )
        )
    }

    func testStateByApplyingRejectsWasteTopKing() {
        let state = GameStateFixtures.golfState(
            columns: [[TestCards.make(.spades, .queen)]],
            waste: [TestCards.make(.diamonds, .king)]
        )
        XCTAssertNil(
            GolfGameRules.stateByApplying(
                selection: exposedSelection(column: 0, in: state),
                destination: .waste,
                to: state
            )
        )
    }

    // MARK: Advisor

    func testAdvisorCandidatesAreExposedCardsOnly() {
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.spades, .nine), TestCards.make(.hearts, .seven)],
                [TestCards.make(.clubs, .three)],
                []
            ],
            waste: [TestCards.make(.diamonds, .six)]
        )

        let selections = GolfAutoMoveAdvisor.candidateSelections(in: state)

        XCTAssertEqual(selections.count, 2)
        XCTAssertTrue(selections.allSatisfy { $0.cards.count == 1 })
        XCTAssertEqual(
            Set(selections.compactMap { $0.cards.first?.rank }),
            Set([Rank.seven, Rank.three])
        )
    }

    func testAdvisorDestinationsAreWasteExactlyWhenPlayable() {
        let state = GameStateFixtures.golfState(
            columns: [
                [TestCards.make(.hearts, .seven)],
                [TestCards.make(.clubs, .three)]
            ],
            waste: [TestCards.make(.diamonds, .six)]
        )

        XCTAssertEqual(
            GolfAutoMoveAdvisor.legalDestinations(
                for: exposedSelection(column: 0, in: state),
                in: state
            ),
            [.waste]
        )
        XCTAssertEqual(
            GolfAutoMoveAdvisor.legalDestinations(
                for: exposedSelection(column: 1, in: state),
                in: state
            ),
            []
        )
    }

    func testAdvisorSimulatedStateMatchesRules() {
        let state = GameStateFixtures.seededGolfDeal(seed: 7)

        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                let simulated = AutoMoveAdvisor.simulatedState(
                    afterMoving: selection,
                    to: destination,
                    in: state,
                    stockDrawCount: 1
                )
                let applied = GolfGameRules.stateByApplying(
                    selection: selection,
                    destination: destination,
                    to: state
                )
                XCTAssertEqual(simulated, applied)
            }
        }
    }
}
