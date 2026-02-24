import XCTest
@testable import Computer_Solitaire

@MainActor
final class FreeCellRulesTests: XCTestCase {
    func testFreeCellNewGameLayout() {
        let state = GameState.newGame(variant: .freecell)

        XCTAssertEqual(state.variant, .freecell)
        XCTAssertEqual(state.stock.count, 0)
        XCTAssertEqual(state.waste.count, 0)
        XCTAssertEqual(state.wasteDrawCount, 0)
        XCTAssertEqual(state.freeCells.count, 4)
        XCTAssertTrue(state.freeCells.allSatisfy { $0 == nil })
        XCTAssertEqual(state.foundations.count, 4)
        XCTAssertEqual(state.tableau.count, 8)
        XCTAssertEqual(state.tableau.prefix(4).map(\.count), [7, 7, 7, 7])
        XCTAssertEqual(state.tableau.suffix(4).map(\.count), [6, 6, 6, 6])
        XCTAssertTrue(state.tableau.joined().allSatisfy(\.isFaceUp))
    }

    func testCanMoveToEmptyTableauDiffersByVariant() {
        let queen = TestCards.make(.hearts, .queen, isFaceUp: true)

        XCTAssertFalse(
            GameRules.canMoveToTableau(
                card: queen,
                destinationPile: [],
                variant: .klondike
            )
        )
        XCTAssertTrue(
            GameRules.canMoveToTableau(
                card: queen,
                destinationPile: [],
                variant: .freecell
            )
        )
    }

    func testFreeCellTransferCountUsesFreeCellsAndEmptyCascades() {
        let occupiedCellCard = TestCards.make(.spades, .ace, isFaceUp: true)
        let freeCells: [Card?] = [nil, nil, occupiedCellCard, occupiedCellCard]
        let tableau: [[Card]] = [
            [TestCards.make(.clubs, .king, isFaceUp: true)],
            [],
            [],
            [TestCards.make(.diamonds, .queen, isFaceUp: true)],
            [TestCards.make(.hearts, .jack, isFaceUp: true)],
            [TestCards.make(.spades, .ten, isFaceUp: true)],
            [TestCards.make(.clubs, .nine, isFaceUp: true)],
            [TestCards.make(.diamonds, .eight, isFaceUp: true)]
        ]

        let transferCount = GameRules.maxFreeCellTransferCount(
            freeCellSlots: freeCells,
            tableau: tableau,
            destination: .tableau(0)
        )

        XCTAssertEqual(transferCount, 12)
    }

    func testFreeCellMoveFromCascadeToFreeCell() {
        var state = GameState.newGame(variant: .freecell)
        let pileIndex = 0
        let cardIndex = state.tableau[pileIndex].count - 1
        let card = state.tableau[pileIndex][cardIndex]

        let selection = Selection(
            source: .tableau(pile: pileIndex, index: cardIndex),
            cards: [card]
        )
        let legalDestinations = AutoMoveAdvisor.legalDestinations(for: selection, in: state)

        XCTAssertTrue(legalDestinations.contains(.freeCell(0)))

        state.tableau[pileIndex].removeLast()
        state.freeCells[0] = card
        XCTAssertEqual(state.freeCells[0]?.id, card.id)
    }
}
