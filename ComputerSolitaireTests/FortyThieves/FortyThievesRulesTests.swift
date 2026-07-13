import XCTest
@testable import Computer_Solitaire

@MainActor
final class FortyThievesRulesTests: XCTestCase {
    // MARK: - Tableau landing

    func testTableauLandingRequiresSameSuitOneRankLower() {
        let eightSpades = [TestCards.make(.spades, .eight)]

        XCTAssertTrue(
            FortyThievesGameRules.canMoveToTableau(
                card: TestCards.make(.spades, .seven),
                destinationPile: eightSpades
            )
        )
        XCTAssertFalse(
            FortyThievesGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .seven),
                destinationPile: eightSpades
            ),
            "An off-suit card must not land, whatever its rank"
        )
        XCTAssertFalse(
            FortyThievesGameRules.canMoveToTableau(
                card: TestCards.make(.spades, .six),
                destinationPile: eightSpades
            ),
            "Building skips no ranks"
        )
        XCTAssertFalse(
            FortyThievesGameRules.canMoveToTableau(
                card: TestCards.make(.spades, .nine),
                destinationPile: eightSpades
            ),
            "Building runs downward only"
        )
    }

    func testNothingLandsOnAnAce() {
        let aceClubs = [TestCards.make(.clubs, .ace)]
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                XCTAssertFalse(
                    FortyThievesGameRules.canMoveToTableau(
                        card: TestCards.make(suit, rank),
                        destinationPile: aceClubs
                    )
                )
            }
        }
    }

    func testEmptyColumnAcceptsAnyAvailableCard() {
        XCTAssertTrue(
            FortyThievesGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .king),
                destinationPile: []
            )
        )
        XCTAssertTrue(
            FortyThievesGameRules.canMoveToTableau(
                card: TestCards.make(.clubs, .five),
                destinationPile: []
            ),
            "Empty columns take any card, not just Kings"
        )

        // Both an exposed tableau card and the waste top reach the empty
        // column through the shared move generation.
        let fiveDiamonds = TestCards.make(.diamonds, .five)
        let nineClubs = TestCards.make(.clubs, .nine)
        let state = GameStateFixtures.fortyThievesState(
            columns: [[TestCards.make(.hearts, .queen), fiveDiamonds]],
            waste: [nineClubs]
        )
        let boardSelection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [state.tableau[0][1]]
        )
        XCTAssertTrue(
            AutoMoveAdvisor.legalDestinations(for: boardSelection, in: state)
                .contains(.tableau(1))
        )
        let wasteSelection = Selection(source: .waste, cards: [state.waste[0]])
        XCTAssertTrue(
            AutoMoveAdvisor.legalDestinations(for: wasteSelection, in: state)
                .contains(.tableau(1))
        )
    }

    // MARK: - Single-card movement

    func testOnlyASingleCardMayBePickedUp() {
        // The defining strictness: even a perfect suited descending run never
        // moves as a unit.
        let viewModel = SolitaireViewModel(variant: .fortyThieves)
        let run = [TestCards.make(.spades, .eight), TestCards.make(.spades, .seven)]

        XCTAssertTrue(viewModel.canSelectTableauCards([run[1]]))
        XCTAssertFalse(viewModel.canSelectTableauCards(run))
    }

    func testBuriedCardDragIsRefused() {
        let viewModel = SolitaireViewModel(variant: .fortyThieves)
        viewModel.state = GameStateFixtures.fortyThievesState(
            columns: [[TestCards.make(.spades, .eight), TestCards.make(.spades, .seven)]]
        )

        XCTAssertFalse(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 0))
        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 1))
    }

    func testCandidateSelectionsOfferOnlyExposedTopCards() {
        let state = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.spades, .eight), TestCards.make(.spades, .seven)],
                [TestCards.make(.hearts, .four)]
            ],
            waste: [TestCards.make(.clubs, .two)]
        )

        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            XCTAssertEqual(selection.cards.count, 1)
            if case .tableau(let pile, let index) = selection.source {
                XCTAssertEqual(index, state.tableau[pile].count - 1)
            }
        }
    }

    // MARK: - Foundations

    func testBothTwinFoundationsProgressIndependently() {
        let aceSpades = TestCards.make(.spades, .ace)
        let twoSpades = TestCards.make(.spades, .two)

        XCTAssertTrue(GameRules.canMoveToFoundation(card: aceSpades, foundation: []))
        // Two decks carry two aces per suit; each starts its own foundation,
        // and a deuce continues either one.
        XCTAssertTrue(GameRules.canMoveToFoundation(card: twoSpades, foundation: [aceSpades]))

        let state = GameStateFixtures.fortyThievesState(
            columns: [[twoSpades]],
            foundations: [[aceSpades], [TestCards.make(.spades, .ace)]]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: [state.tableau[0][0]])
        let destinations = AutoMoveAdvisor.legalDestinations(for: selection, in: state)
        XCTAssertTrue(destinations.contains(.foundation(0)))
        XCTAssertTrue(destinations.contains(.foundation(1)))
    }

    func testSafeFoundationMoveRequiresBothTwinFoundationsCaughtUp() {
        let fiveSpades = TestCards.make(.spades, .five)
        func spadeFoundation(through rank: Int) -> [Card] {
            Rank.allCases.filter { $0.rawValue <= rank }.map { TestCards.make(.spades, $0) }
        }

        // Aces and twos can never be needed as a tableau landing spot.
        XCTAssertTrue(
            FortyThievesGameRules.isSafeFoundationMove(
                card: TestCards.make(.hearts, .ace),
                in: GameStateFixtures.fortyThievesState(columns: [])
            )
        )
        XCTAssertTrue(
            FortyThievesGameRules.isSafeFoundationMove(
                card: TestCards.make(.hearts, .two),
                in: GameStateFixtures.fortyThievesState(columns: [])
            )
        )

        // Rank five is safe only once both spade foundations reach three —
        // then every four of spades is directly foundation-playable and never
        // needs the five as a landing spot.
        let bothCaughtUp = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [spadeFoundation(through: 3), spadeFoundation(through: 3)]
        )
        XCTAssertTrue(FortyThievesGameRules.isSafeFoundationMove(card: fiveSpades, in: bothCaughtUp))

        let oneLagging = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [spadeFoundation(through: 3), spadeFoundation(through: 2)]
        )
        XCTAssertFalse(FortyThievesGameRules.isSafeFoundationMove(card: fiveSpades, in: oneLagging))

        let oneUnstarted = GameStateFixtures.fortyThievesState(
            columns: [],
            foundations: [spadeFoundation(through: 13)]
        )
        XCTAssertFalse(
            FortyThievesGameRules.isSafeFoundationMove(card: fiveSpades, in: oneUnstarted),
            "An unstarted twin foundation still owes its whole run"
        )
    }

    // MARK: - Foundation lock

    func testFoundationCardsNeverReturnToPlay() {
        let viewModel = SolitaireViewModel(variant: .fortyThieves)
        viewModel.state = GameStateFixtures.fortyThievesState(
            columns: [[TestCards.make(.spades, .three)]],
            foundations: [[TestCards.make(.spades, .ace), TestCards.make(.spades, .two)]]
        )

        XCTAssertFalse(viewModel.startDragFromFoundation(index: 0))
        viewModel.selectFromFoundation(index: 0)
        XCTAssertNil(viewModel.selection)

        // The advisor never offers a foundation source, and even a
        // hand-constructed one is refused every tableau landing — the 2♠ may
        // not come back down onto the 3♠.
        let selections = AutoMoveAdvisor.candidateSelections(in: viewModel.state)
        XCTAssertFalse(selections.contains { selection in
            if case .foundation = selection.source { return true }
            return false
        })

        guard let top = viewModel.state.foundations[0].last else {
            return XCTFail("Expected a foundation top")
        }
        let rollback = Selection(source: .foundation(pile: 0), cards: [top])
        let destinations = AutoMoveAdvisor.legalDestinations(for: rollback, in: viewModel.state)
        XCTAssertFalse(destinations.contains { destination in
            if case .tableau = destination { return true }
            return false
        })
    }

    func testTapPolicyOrdersSafeFoundationBuildUnsafeFoundationEmptyColumn() {
        func spadeFoundation(through rank: Int) -> [Card] {
            Rank.allCases.filter { $0.rawValue <= rank }.map { TestCards.make(.spades, $0) }
        }

        // 5♠ with both spade foundations at four: banking is safe and wins
        // over the tableau build onto the 6♠. A base card keeps the empty
        // column a genuine (non-redundant) alternative throughout.
        let safeState = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .nine), TestCards.make(.spades, .five)],
                [TestCards.make(.spades, .six)]
            ],
            foundations: [spadeFoundation(through: 4), spadeFoundation(through: 4)]
        )
        let safeSelection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [safeState.tableau[0][1]]
        )
        XCTAssertEqual(
            TapMovePolicy.bestDestination(for: safeSelection, in: safeState),
            .foundation(0)
        )

        // With the twin foundation lagging the bank is unsafe, so the tableau
        // build wins; with no build available the unsafe bank still beats the
        // empty column.
        let unsafeState = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .nine), TestCards.make(.spades, .five)],
                [TestCards.make(.spades, .six)]
            ],
            foundations: [spadeFoundation(through: 4), spadeFoundation(through: 1)]
        )
        let unsafeSelection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [unsafeState.tableau[0][1]]
        )
        XCTAssertEqual(
            TapMovePolicy.bestDestination(for: unsafeSelection, in: unsafeState),
            .tableau(1)
        )

        let noBuildState = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .nine), TestCards.make(.spades, .five)],
                [TestCards.make(.hearts, .queen)]
            ],
            foundations: [spadeFoundation(through: 4), spadeFoundation(through: 1)]
        )
        let noBuildSelection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [noBuildState.tableau[0][1]]
        )
        XCTAssertEqual(
            TapMovePolicy.bestDestination(for: noBuildSelection, in: noBuildState),
            .foundation(0),
            "An unsafe bank still beats spending an empty column"
        )
    }
}
