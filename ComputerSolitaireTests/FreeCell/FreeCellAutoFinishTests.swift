import XCTest
@testable import Computer_Solitaire

@MainActor
final class FreeCellAutoFinishTests: XCTestCase {
    func testCanAutoFinishWhenRemainingBoardIsAPureFoundationRun() {
        let state = freeCellEndgame(
            freeCells: [TestCards.make(.clubs, .king), nil, nil, nil],
            highestFoundationRank: .queen,
            tableau: [
                [TestCards.make(.spades, .king)],
                [TestCards.make(.hearts, .king)],
                [TestCards.make(.diamonds, .king)],
                [], [], [], [], []
            ]
        )
        XCTAssertTrue(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testCanAutoFinishDrainsCardsInDescendingOrderWithinPiles() {
        // Piles are ordered top-to-bottom correctly for foundation play (queen under king
        // would block; king under queen plays out).
        let state = freeCellEndgame(
            freeCells: [nil, nil, nil, nil],
            highestFoundationRank: .jack,
            tableau: [
                [TestCards.make(.spades, .king), TestCards.make(.spades, .queen)],
                [TestCards.make(.hearts, .king), TestCards.make(.hearts, .queen)],
                [TestCards.make(.diamonds, .king), TestCards.make(.diamonds, .queen)],
                [TestCards.make(.clubs, .king), TestCards.make(.clubs, .queen)],
                [], [], [], []
            ]
        )
        XCTAssertTrue(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testCannotAutoFinishWhenACardIsBuriedOutOfOrder() {
        // Queen buried UNDER the king: the queen can never play before the king,
        // and the king needs the queen's spot first → not a pure foundation run.
        let state = freeCellEndgame(
            freeCells: [nil, nil, nil, nil],
            highestFoundationRank: .jack,
            tableau: [
                [TestCards.make(.spades, .queen), TestCards.make(.spades, .king)],
                [TestCards.make(.hearts, .king), TestCards.make(.hearts, .queen)],
                [TestCards.make(.diamonds, .king), TestCards.make(.diamonds, .queen)],
                [TestCards.make(.clubs, .king), TestCards.make(.clubs, .queen)],
                [], [], [], []
            ]
        )
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testNextAutoFinishMovePullsFromFreeCellWhenNeeded() {
        // Spades foundation stops at jack; every other suit is at queen. The only
        // queen-rank play is the Q♠ waiting in a free cell.
        let queenSpades = TestCards.make(.spades, .queen)
        var foundations = Array(repeating: [Card](), count: 4)
        for (index, suit) in Suit.allCases.enumerated() {
            let topRank: Rank = suit == .spades ? .jack : .queen
            foundations[index] = Rank.allCases
                .filter { $0.rawValue <= topRank.rawValue }
                .map { TestCards.make(suit, $0) }
        }
        let state = GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: [nil, queenSpades, nil, nil],
            foundations: foundations,
            tableau: [
                [TestCards.make(.spades, .king)],
                [TestCards.make(.hearts, .king)],
                [TestCards.make(.diamonds, .king)],
                [TestCards.make(.clubs, .king)],
                [], [], [], []
            ]
        )

        XCTAssertTrue(AutoFinishPlanner.canAutoFinish(in: state))
        let move = AutoFinishPlanner.nextAutoFinishMove(in: state)
        XCTAssertEqual(move?.selection.cards.first?.id, queenSpades.id)
        if case .freeCell(let slot) = move?.selection.source {
            XCTAssertEqual(slot, 1)
        } else {
            XCTFail("Expected the free-cell queen to be the next auto-finish move")
        }
    }

    func testCascadeGateRejectsSameSuitPairBuriedLowestFirst() {
        // The 5♠ under the 9♠ must reach the foundation before the 9♠ can,
        // but only the 9♠'s removal exposes it — impossible, so the position
        // must be rejected (and cheaply, without the win simulation).
        let state = freeCellEndgame(
            freeCells: [nil, nil, nil, nil],
            highestFoundationRank: .two,
            tableau: [
                [TestCards.make(.spades, .five), TestCards.make(.spades, .nine)],
                [TestCards.make(.hearts, .four), TestCards.make(.hearts, .three)],
                [], [], [], [], [], []
            ]
        )
        XCTAssertFalse(AutoFinishPlanner.freeCellCascadesAllowFoundationRun(state))
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testCascadeGatePassesCrossSuitBurialsForTheSimulationToJudge() {
        // A♠ under K♥ violates no same-suit ordering, so the cheap gate must
        // pass it — and the simulation must still reject it, because the K♥
        // cannot reach the hearts foundation before the buried ace plays.
        let state = freeCellEndgame(
            freeCells: [nil, nil, nil, nil],
            highestFoundationRank: .ace,
            tableau: [
                [TestCards.make(.spades, .two), TestCards.make(.hearts, .king)],
                [TestCards.make(.hearts, .two)],
                [], [], [], [], [], []
            ]
        )
        XCTAssertTrue(AutoFinishPlanner.freeCellCascadesAllowFoundationRun(state))
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    /// Builds a FreeCell endgame where every suit's foundation is filled up to
    /// `highestFoundationRank` and the remaining cards sit in the given layout.
    private func freeCellEndgame(
        freeCells: [Card?],
        highestFoundationRank: Rank,
        tableau: [[Card]]
    ) -> GameState {
        var foundations = Array(repeating: [Card](), count: 4)
        for (index, suit) in Suit.allCases.enumerated() {
            foundations[index] = Rank.allCases
                .filter { $0.rawValue <= highestFoundationRank.rawValue }
                .map { TestCards.make(suit, $0) }
        }
        return GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: freeCells,
            foundations: foundations,
            tableau: tableau
        )
    }
}
