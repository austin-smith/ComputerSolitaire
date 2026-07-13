import XCTest
@testable import Computer_Solitaire

@MainActor
final class YukonRulesTests: XCTestCase {
    func testYukonNewGameLayout() {
        let state = GameState.newGame(variant: .yukon)

        XCTAssertEqual(state.variant, .yukon)
        XCTAssertTrue(state.stock.isEmpty)
        XCTAssertTrue(state.waste.isEmpty)
        XCTAssertEqual(state.wasteDrawCount, 0)
        XCTAssertTrue(state.freeCells.allSatisfy { $0 == nil })
        XCTAssertEqual(state.foundations.count, 4)
        XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
        XCTAssertEqual(state.tableau.map(\.count), [1, 6, 7, 8, 9, 10, 11])

        for (pileIndex, pile) in state.tableau.enumerated() {
            let expectedFaceDownCount = pileIndex == 0 ? 0 : pileIndex
            let faceDownPrefix = pile.prefix(while: { !$0.isFaceUp })
            XCTAssertEqual(faceDownPrefix.count, expectedFaceDownCount, "Pile \(pileIndex)")
            XCTAssertTrue(
                pile.dropFirst(expectedFaceDownCount).allSatisfy(\.isFaceUp),
                "Pile \(pileIndex): face-up cards must sit above the face-down ones"
            )
        }

        let allCards = Array(state.tableau.joined())
        XCTAssertEqual(allCards.count, 52)
        XCTAssertEqual(Set(allCards.map(\.id)).count, 52)
    }

    func testTableauLandingRuleMatchesKlondikeSemantics() {
        let sevenHearts = TestCards.make(.hearts, .seven)
        let eightSpades = TestCards.make(.spades, .eight)
        let eightDiamonds = TestCards.make(.diamonds, .eight)
        let nineSpades = TestCards.make(.spades, .nine)
        let queenHearts = TestCards.make(.hearts, .queen)
        let kingClubs = TestCards.make(.clubs, .king)
        let faceDownEight = TestCards.make(.spades, .eight, isFaceUp: false)

        // Opposite color, one rank higher: legal.
        XCTAssertTrue(GameRules.canMoveToTableau(card: sevenHearts, destinationPile: [eightSpades], variant: .yukon))
        // Same color: rejected.
        XCTAssertFalse(GameRules.canMoveToTableau(card: sevenHearts, destinationPile: [eightDiamonds], variant: .yukon))
        // Wrong rank: rejected.
        XCTAssertFalse(GameRules.canMoveToTableau(card: sevenHearts, destinationPile: [nineSpades], variant: .yukon))
        // Face-down destination top: rejected.
        XCTAssertFalse(GameRules.canMoveToTableau(card: sevenHearts, destinationPile: [faceDownEight], variant: .yukon))
        // Empty column: Kings only.
        XCTAssertTrue(GameRules.canMoveToTableau(card: kingClubs, destinationPile: [], variant: .yukon))
        XCTAssertFalse(GameRules.canMoveToTableau(card: queenHearts, destinationPile: [], variant: .yukon))
    }

    func testUnorderedGroupMovesThroughTheSession() {
        let hiddenFour = TestCards.make(.diamonds, .four, isFaceUp: false)
        let sevenHearts = TestCards.make(.hearts, .seven)
        let twoSpades = TestCards.make(.spades, .two)
        let eightSpades = TestCards.make(.spades, .eight)

        let viewModel = SolitaireViewModel()
        viewModel.newGame(mode: .yukon)
        viewModel.state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenFour, sevenHearts, twoSpades], [eightSpades], [], [], [], [], []]
        )

        // The 7♥/2♠ group is not a sequence, yet Yukon allows picking it up; only the
        // bottom card (7♥) has to fit the destination (8♠).
        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 1))
        XCTAssertTrue(viewModel.canDrop(to: .tableau(1)))
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))

        XCTAssertEqual(viewModel.state.tableau[1].map(\.rank), [.eight, .seven, .two])
        XCTAssertEqual(viewModel.state.tableau[0].count, 1)
        XCTAssertTrue(
            viewModel.state.tableau[0][0].isFaceUp,
            "The exposed face-down card must flip when the group moves away"
        )
    }

    func testDroppingAGroupBackOntoItsOwnPileIsARejectedCancel() {
        // In Yukon an unordered group's bottom card can "fit" the top card of its own
        // pile (8♥ under 9♠ fits on 9♠), so without an explicit same-pile rejection a
        // cancelled drag would count as a move and flip the hidden card for free.
        let hiddenFour = TestCards.make(.diamonds, .four, isFaceUp: false)
        let eightHearts = TestCards.make(.hearts, .eight)
        let nineSpades = TestCards.make(.spades, .nine)

        let viewModel = SolitaireViewModel()
        viewModel.newGame(mode: .yukon)
        viewModel.state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenFour, eightHearts, nineSpades], [], [], [], [], [], []]
        )
        let movesBefore = viewModel.movesCount
        let scoreBefore = viewModel.score

        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 1))
        XCTAssertFalse(viewModel.canDrop(to: .tableau(0)))
        XCTAssertFalse(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertEqual(viewModel.movesCount, movesBefore)
        XCTAssertEqual(viewModel.score, scoreBefore)
        XCTAssertFalse(
            viewModel.state.tableau[0][0].isFaceUp,
            "A cancelled same-pile drop must not flip the hidden card"
        )
    }

    func testKingLedUnorderedGroupFillsEmptyColumnAndOthersCannot() {
        let kingSpades = TestCards.make(.spades, .king)
        let fiveDiamonds = TestCards.make(.diamonds, .five)
        let hiddenNine = TestCards.make(.clubs, .nine, isFaceUp: false)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenNine, kingSpades, fiveDiamonds], [], [], [], [], [], []]
        )

        let kingGroup = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [kingSpades, fiveDiamonds]
        )
        XCTAssertTrue(AutoMoveAdvisor.legalDestinations(for: kingGroup, in: state).contains(.tableau(1)))

        let nonKingGroup = Selection(source: .tableau(pile: 0, index: 2), cards: [fiveDiamonds])
        XCTAssertFalse(
            AutoMoveAdvisor.legalDestinations(for: nonKingGroup, in: state)
                .contains(where: { if case .tableau = $0 { return true } else { return false } })
        )
    }

    func testSimulatedStateFlipsExposedCard() {
        let hiddenTen = TestCards.make(.hearts, .ten, isFaceUp: false)
        let threeClubs = TestCards.make(.clubs, .three)
        let fourHearts = TestCards.make(.hearts, .four)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenTen, threeClubs], [fourHearts], [], [], [], [], []]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 1), cards: [threeClubs])

        let nextState = AutoMoveAdvisor.simulatedState(
            afterMoving: selection,
            to: .tableau(1),
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        )
        XCTAssertNotNil(nextState)
        XCTAssertTrue(nextState?.tableau[0].last?.isFaceUp ?? false)
    }

    func testFoundationTopReturnsToTableau() {
        let aceSpades = TestCards.make(.spades, .ace)
        let twoSpades = TestCards.make(.spades, .two)
        let threeHearts = TestCards.make(.hearts, .three)

        let viewModel = SolitaireViewModel()
        viewModel.newGame(mode: .yukon)
        viewModel.state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[aceSpades, twoSpades], [], [], []],
            tableau: [[threeHearts], [], [], [], [], [], []]
        )

        viewModel.selectFromFoundation(index: 0)
        XCTAssertTrue(viewModel.canDrop(to: .tableau(0)))
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))
        XCTAssertEqual(viewModel.state.tableau[0].map(\.rank), [.three, .two])
    }

    func testYukonMoveScoring() {
        let aceSpades = TestCards.make(.spades, .ace)
        let hiddenSix = TestCards.make(.hearts, .six, isFaceUp: false)

        let viewModel = SolitaireViewModel()
        viewModel.newGame(mode: .yukon)
        viewModel.state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [[hiddenSix, aceSpades], [], [], [], [], [], []]
        )
        let baseScore = viewModel.score

        // Tableau -> foundation banks the ace and flips the exposed card underneath.
        viewModel.selectFromTableau(pileIndex: 0, cardIndex: 1)
        XCTAssertTrue(viewModel.tryMoveSelection(to: .foundation(0)))
        XCTAssertEqual(
            viewModel.score,
            baseScore
                + Scoring.delta(for: .tableauToFoundation)
                + Scoring.delta(for: .turnOverTableauCard)
        )

        // Foundation -> tableau costs points, exactly like Klondike.
        let scoreBeforeRollback = viewModel.score
        let twoHearts = TestCards.make(.hearts, .two)
        viewModel.state.tableau[1] = [twoHearts]
        viewModel.selectFromFoundation(index: 0)
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))
        XCTAssertEqual(viewModel.score, scoreBeforeRollback + Scoring.delta(for: .foundationToTableau))
    }
}
