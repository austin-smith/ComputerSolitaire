import XCTest
@testable import Computer_Solitaire

@MainActor
final class GameRulesTests: XCTestCase {
    func testCanMoveToFoundationRequiresAceOnEmptyFoundation() {
        XCTAssertTrue(
            GameRules.canMoveToFoundation(
                card: TestCards.make(.spades, .ace),
                foundation: []
            )
        )
        XCTAssertFalse(
            GameRules.canMoveToFoundation(
                card: TestCards.make(.spades, .two),
                foundation: []
            )
        )
    }

    func testCanMoveToFoundationRequiresSameSuitAndAscendingRank() {
        let foundation = [
            TestCards.make(.hearts, .ace),
            TestCards.make(.hearts, .two),
            TestCards.make(.hearts, .three)
        ]

        XCTAssertTrue(
            GameRules.canMoveToFoundation(
                card: TestCards.make(.hearts, .four),
                foundation: foundation
            )
        )
        XCTAssertFalse(
            GameRules.canMoveToFoundation(
                card: TestCards.make(.spades, .four),
                foundation: foundation
            )
        )
        XCTAssertFalse(
            GameRules.canMoveToFoundation(
                card: TestCards.make(.hearts, .five),
                foundation: foundation
            )
        )
    }

    func testCanMoveToTableauRequiresKingOnEmptyPile() {
        XCTAssertTrue(
            GameRules.canMoveToTableau(
                card: TestCards.make(.clubs, .king),
                destinationPile: []
            )
        )
        XCTAssertFalse(
            GameRules.canMoveToTableau(
                card: TestCards.make(.clubs, .queen),
                destinationPile: []
            )
        )
    }

    func testCanMoveToTableauRequiresAlternatingColorAndDescendingRank() {
        let destination = [TestCards.make(.spades, .seven, isFaceUp: true)]

        XCTAssertTrue(
            GameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .six),
                destinationPile: destination
            )
        )
        XCTAssertFalse(
            GameRules.canMoveToTableau(
                card: TestCards.make(.clubs, .six),
                destinationPile: destination
            )
        )
        XCTAssertFalse(
            GameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .five),
                destinationPile: destination
            )
        )
    }

    func testCanMoveToTableauRejectsFaceDownDestinationTopCard() {
        let destination = [TestCards.make(.spades, .seven, isFaceUp: false)]
        XCTAssertFalse(
            GameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .six),
                destinationPile: destination
            )
        )
    }
}
