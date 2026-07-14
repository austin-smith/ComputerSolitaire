import XCTest
@testable import Computer_Solitaire

@MainActor
final class CanfieldRulesTests: XCTestCase {
    // MARK: - Foundations

    func testEmptyFoundationTakesOnlyTheBaseRank() {
        // Base rank five: the deal seeded 5♠ onto the first foundation.
        let state = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [[TestCards.make(.spades, .five)]]
        )

        XCTAssertTrue(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.hearts, .five),
                foundation: state.foundations[1],
                in: state
            )
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.hearts, .ace),
                foundation: state.foundations[1],
                in: state
            ),
            "An Ace is just another rank when the base is a five"
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.hearts, .six),
                foundation: state.foundations[1],
                in: state
            ),
            "A started foundation's neighbor rank must not seed a new pile"
        )
    }

    func testFoundationBuildsUpBySuitTurningTheCorner() {
        let state = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [
                [TestCards.make(.spades, .queen)],
                [TestCards.make(.hearts, .queen), TestCards.make(.hearts, .king)]
            ]
        )

        XCTAssertTrue(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.spades, .king),
                foundation: state.foundations[0],
                in: state
            )
        )
        XCTAssertTrue(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.hearts, .ace),
                foundation: state.foundations[1],
                in: state
            ),
            "Foundations turn the corner from King to Ace"
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.clubs, .ace),
                foundation: state.foundations[1],
                in: state
            ),
            "Foundations build one suit only"
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToFoundation(
                card: TestCards.make(.spades, .jack),
                foundation: state.foundations[0],
                in: state
            ),
            "Foundations build upward only"
        )
    }

    func testBaseRankReadsOffTheFirstSeededFoundation() {
        let state = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [[], [TestCards.make(.diamonds, .nine)]]
        )
        XCTAssertEqual(CanfieldGameRules.baseRank(in: state), .nine)

        let unseeded = GameStateFixtures.canfieldState(columns: [])
        XCTAssertNil(CanfieldGameRules.baseRank(in: unseeded))
    }

    // MARK: - Tableau landings

    func testTableauLandingRequiresOppositeColorOneRankLower() {
        let eightSpades = [TestCards.make(.spades, .eight)]

        XCTAssertTrue(
            CanfieldGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .seven),
                destinationPile: eightSpades
            )
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToTableau(
                card: TestCards.make(.clubs, .seven),
                destinationPile: eightSpades
            ),
            "A same-color card must not land, whatever its rank"
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .six),
                destinationPile: eightSpades
            ),
            "Building skips no ranks"
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .nine),
                destinationPile: eightSpades
            ),
            "Building runs downward only"
        )
    }

    func testTableauBuildingTurnsTheCornerFromAceToKing() {
        let aceHearts = [TestCards.make(.hearts, .ace)]
        XCTAssertTrue(
            CanfieldGameRules.canMoveToTableau(
                card: TestCards.make(.spades, .king),
                destinationPile: aceHearts
            ),
            "A King packs on an Ace when the sequence turns the corner"
        )
        XCTAssertFalse(
            CanfieldGameRules.canMoveToTableau(
                card: TestCards.make(.diamonds, .king),
                destinationPile: aceHearts
            )
        )
    }

    func testPackedSequenceValidationTurnsTheCorner() {
        XCTAssertTrue(
            CanfieldGameRules.isPackedSequence([
                TestCards.make(.spades, .two),
                TestCards.make(.hearts, .ace),
                TestCards.make(.clubs, .king)
            ])
        )
        XCTAssertFalse(
            CanfieldGameRules.isPackedSequence([
                TestCards.make(.spades, .two),
                TestCards.make(.clubs, .ace)
            ]),
            "Packing alternates colors"
        )
        XCTAssertFalse(
            CanfieldGameRules.isPackedSequence([
                TestCards.make(.spades, .two),
                TestCards.make(.hearts, .king)
            ]),
            "Packing descends one rank per step"
        )
    }

    // MARK: - Whole-pile movement

    func testOnlyTheWholePileOrItsTopCardMayBePickedUp() {
        let viewModel = SolitaireViewModel(variant: .canfield)
        let pile = [
            TestCards.make(.spades, .eight),
            TestCards.make(.hearts, .seven),
            TestCards.make(.clubs, .six)
        ]
        viewModel.state = GameStateFixtures.canfieldState(columns: [pile])

        XCTAssertTrue(viewModel.canSelectTableauCards(viewModel.state.tableau[0]))
        XCTAssertTrue(viewModel.canSelectTableauCards([viewModel.state.tableau[0][2]]))
        XCTAssertFalse(
            viewModel.canSelectTableauCards(Array(viewModel.state.tableau[0][1...])),
            "A partial sequence never moves, however well packed"
        )
    }

    func testBuriedCardDragIsRefusedAndEdgesAreAllowed() {
        let viewModel = SolitaireViewModel(variant: .canfield)
        viewModel.state = GameStateFixtures.canfieldState(
            columns: [[
                TestCards.make(.spades, .eight),
                TestCards.make(.hearts, .seven),
                TestCards.make(.clubs, .six)
            ]]
        )

        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 0))
        viewModel.cancelDrag()
        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 2))
        viewModel.cancelDrag()
        XCTAssertFalse(
            viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 1),
            "A mid-pile drag would be a partial sequence"
        )
    }

    func testTopCardOfALongerPileNeverTransfersBetweenPiles() {
        // 7♥ could pack on the other pile's 8♣ — but lifting it off the 8♠
        // would split the pile, so only the whole pile may go (and it cannot,
        // since its bottom card is the same rank).
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.spades, .eight), TestCards.make(.hearts, .seven)],
                [TestCards.make(.clubs, .eight)]
            ],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        let topCardSelection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [state.tableau[0][1]]
        )
        XCTAssertFalse(
            AutoMoveAdvisor.legalDestinations(for: topCardSelection, in: state)
                .contains(.tableau(1))
        )
    }

    func testWholePileTransfersWhenTheJoinIsLegal() {
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.hearts, .seven), TestCards.make(.clubs, .six)],
                [TestCards.make(.spades, .eight)]
            ],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        let wholePile = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: state.tableau[0]
        )
        XCTAssertTrue(
            AutoMoveAdvisor.legalDestinations(for: wholePile, in: state)
                .contains(.tableau(1))
        )
    }

    // MARK: - Empty piles

    func testEmptyPileTakesOnlyTheWasteTopOnceTheReserveIsOut() {
        let state = GameStateFixtures.canfieldState(
            columns: [
                [],
                [TestCards.make(.spades, .eight)],
                [TestCards.make(.hearts, .nine)]
            ],
            waste: [TestCards.make(.clubs, .four)],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )

        let wasteSelection = Selection(source: .waste, cards: [state.waste[0]])
        XCTAssertTrue(
            AutoMoveAdvisor.legalDestinations(for: wasteSelection, in: state)
                .contains(.tableau(0))
        )

        let pileSelection = Selection(
            source: .tableau(pile: 1, index: 0),
            cards: state.tableau[1]
        )
        XCTAssertFalse(
            AutoMoveAdvisor.legalDestinations(for: pileSelection, in: state)
                .contains(.tableau(0)),
            "A space never fills from another tableau pile"
        )
    }

    func testEmptyPileRefusesTheWasteWhileTheReserveHolds() {
        // The invariant keeps spaces from persisting while the reserve holds;
        // a hand-built space must still refuse the waste so the compulsory
        // fill stays the only path.
        let state = GameStateFixtures.canfieldState(
            columns: [[], [TestCards.make(.spades, .eight)]],
            reserve: [TestCards.make(.diamonds, .two)],
            waste: [TestCards.make(.clubs, .four)],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )
        let wasteSelection = Selection(source: .waste, cards: [state.waste[0]])
        XCTAssertFalse(
            AutoMoveAdvisor.legalDestinations(for: wasteSelection, in: state)
                .contains(.tableau(0))
        )
    }

    // MARK: - Reserve

    func testReserveTopIsAvailableToFoundationsAndTableauBuilds() {
        let reserveTop = TestCards.make(.hearts, .seven)
        let state = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.spades, .eight)]],
            reserve: [TestCards.make(.clubs, .three), reserveTop],
            foundations: [[TestCards.make(.diamonds, .seven)]]
        )

        let selections = AutoMoveAdvisor.candidateSelections(in: state)
        let reserveSelection = selections.first { $0.source == .reserve }
        XCTAssertEqual(reserveSelection?.cards.first?.rank, .seven)

        let destinations = AutoMoveAdvisor.legalDestinations(
            for: Selection(source: .reserve, cards: [state.reserve[1]]),
            in: state
        )
        XCTAssertTrue(destinations.contains(.tableau(0)), "Reserve cards build on occupied piles")
        XCTAssertTrue(
            destinations.contains(.foundation(1)),
            "The base-rank reserve top starts an empty foundation"
        )
    }

    func testEmptiedPileRefillsFromTheReserveAtOnce() throws {
        let reserveTop = TestCards.make(.diamonds, .queen)
        let state = GameStateFixtures.canfieldState(
            columns: [
                [TestCards.make(.clubs, .six)],
                [TestCards.make(.hearts, .seven)]
            ],
            reserve: [TestCards.make(.spades, .two), reserveTop],
            foundations: [[TestCards.make(.diamonds, .ten)]]
        )

        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: state.tableau[0])
        let next = AutoMoveAdvisor.simulatedState(
            afterMoving: selection,
            to: .tableau(1),
            in: state,
            stockDrawCount: CanfieldGameRules.stockDrawCount
        )

        let refilled = try XCTUnwrap(next)
        XCTAssertEqual(refilled.tableau[0].first?.id, reserveTop.id)
        XCTAssertEqual(refilled.reserve.count, 1)
        XCTAssertEqual(
            refilled.reserve.last?.isFaceUp,
            true,
            "The next reserve card turns face up"
        )
    }

    // MARK: - Safe foundation sends

    func testBaseAndBasePlusOneAreAlwaysSafe() {
        let state = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [[TestCards.make(.spades, .five)]]
        )
        XCTAssertTrue(
            CanfieldGameRules.isSafeFoundationMove(card: TestCards.make(.hearts, .five), in: state)
        )
        XCTAssertTrue(
            CanfieldGameRules.isSafeFoundationMove(card: TestCards.make(.spades, .six), in: state)
        )
        XCTAssertFalse(
            CanfieldGameRules.isSafeFoundationMove(card: TestCards.make(.spades, .seven), in: state),
            "Two above the base needs the opposite-color foundations developed"
        )
    }

    func testHigherOffsetsFollowTheClassicTwoStepRule() {
        // Base five. Spades at seven means the next spade is offset 3 (an
        // eight); it is safe once both red foundations reach offset 2 and
        // clubs reaches offset 1.
        let state = GameStateFixtures.canfieldState(
            columns: [],
            foundations: [
                [
                    TestCards.make(.spades, .five),
                    TestCards.make(.spades, .six),
                    TestCards.make(.spades, .seven)
                ],
                [TestCards.make(.hearts, .five), TestCards.make(.hearts, .six), TestCards.make(.hearts, .seven)],
                [TestCards.make(.diamonds, .five), TestCards.make(.diamonds, .six), TestCards.make(.diamonds, .seven)],
                [TestCards.make(.clubs, .five), TestCards.make(.clubs, .six)]
            ]
        )
        XCTAssertTrue(
            CanfieldGameRules.isSafeFoundationMove(card: TestCards.make(.spades, .eight), in: state)
        )

        var lagging = state
        lagging.foundations[2].removeLast()
        XCTAssertFalse(
            CanfieldGameRules.isSafeFoundationMove(card: TestCards.make(.spades, .eight), in: lagging),
            "A lagging opposite-color foundation blocks the safe call"
        )
    }
}
