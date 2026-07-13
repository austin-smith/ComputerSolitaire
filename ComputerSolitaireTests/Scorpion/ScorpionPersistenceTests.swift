import XCTest
@testable import Computer_Solitaire

@MainActor
final class ScorpionPersistenceTests: XCTestCase {
    private func payload(for state: GameState) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            stockDrawCount: DrawMode.three.rawValue,
            history: []
        )
    }

    // MARK: - Valid states

    func testFreshDealRoundTrips() throws {
        let state = GameStateFixtures.seededScorpionDeal(seed: 9)
        let sanitized = try XCTUnwrap(
            payload(for: state).sanitizedForRestore(),
            "A fresh deal must pass the validity gate"
        )
        XCTAssertEqual(sanitized.state, state)
        XCTAssertEqual(sanitized.gameMode, .scorpion)

        let viewModel = SolitaireViewModel()
        XCTAssertTrue(viewModel.restore(from: sanitized))
        XCTAssertEqual(viewModel.gameVariant, .scorpion)
    }

    func testPostDealStateIsValid() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        XCTAssertNotNil(ScorpionGameRules.dealStock(in: &state))
        XCTAssertNotNil(payload(for: state).sanitizedForRestore())
    }

    func testMidGameStateWithBankedRunIsValid() {
        // Bank one complete heart run by hand: the board keeps all 52 cards,
        // so the multiset gate still holds. The stock is dealt first so every
        // heart is guaranteed to be somewhere in the tableau.
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        XCTAssertNotNil(ScorpionGameRules.dealStock(in: &state))
        var bankedRun: [Card] = []
        for rank in Rank.allCases {
            let location = firstLocation(
                where: { $0.suit == .hearts && $0.rank == rank },
                in: state.tableau
            )!
            var card = state.tableau[location.pile].remove(at: location.index)
            card.isFaceUp = true
            bankedRun.append(card)
        }
        state.foundations[0] = bankedRun
        for pileIndex in state.tableau.indices {
            if let topIndex = state.tableau[pileIndex].indices.last {
                state.tableau[pileIndex][topIndex].isFaceUp = true
            }
        }
        XCTAssertNotNil(payload(for: state).sanitizedForRestore())
    }

    // MARK: - Rejected states

    func testRejectsPartiallyDealtStock() {
        for remaining in [1, 2] {
            var state = GameStateFixtures.seededScorpionDeal(seed: 9)
            for _ in 0..<(3 - remaining) {
                var card = state.stock.removeLast()
                card.isFaceUp = true
                state.tableau[0].append(card)
            }
            XCTAssertNil(
                payload(for: state).sanitizedForRestore(),
                "The stock deals wholesale: \(remaining) remaining cards cannot occur"
            )
        }
    }

    func testRejectsFaceUpStockCard() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        state.stock[0].isFaceUp = true
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsWrongPileCount() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        let removedPile = state.tableau.removeLast()
        state.tableau[0].append(contentsOf: removedPile)
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsWrongFoundationCount() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        state.foundations = Array(repeating: [], count: 8)
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsNonEmptyWasteAndOccupiedFreeCell() {
        var wasteState = GameStateFixtures.seededScorpionDeal(seed: 9)
        wasteState.waste.append(wasteState.stock.removeLast())
        XCTAssertNil(payload(for: wasteState).sanitizedForRestore())

        var freeCellState = GameStateFixtures.seededScorpionDeal(seed: 9)
        freeCellState.freeCells[0] = freeCellState.stock.removeLast()
        XCTAssertNil(payload(for: freeCellState).sanitizedForRestore())
    }

    func testRejectsPartialOrMixedFoundationPile() {
        // Move five in-suit cards to a foundation: partial banked runs cannot
        // occur. The stock is dealt first so every needed card is in the tableau.
        var partialState = GameStateFixtures.seededScorpionDeal(seed: 9)
        XCTAssertNotNil(ScorpionGameRules.dealStock(in: &partialState))
        var moved: [Card] = []
        for rank in [Rank.ace, .two, .three, .four, .five] {
            let location = firstLocation(
                where: { $0.suit == .hearts && $0.rank == rank },
                in: partialState.tableau
            )!
            moved.append(partialState.tableau[location.pile].remove(at: location.index))
        }
        partialState.foundations[0] = moved
        XCTAssertNil(payload(for: partialState).sanitizedForRestore())

        // A full 13-card foundation pile that mixes suits is equally impossible.
        var mixedState = GameStateFixtures.seededScorpionDeal(seed: 9)
        XCTAssertNotNil(ScorpionGameRules.dealStock(in: &mixedState))
        var mixedRun: [Card] = []
        for rank in Rank.allCases {
            let suit: Suit = rank == .king ? .hearts : .spades
            let location = firstLocation(
                where: { $0.suit == suit && $0.rank == rank },
                in: mixedState.tableau
            )!
            var card = mixedState.tableau[location.pile].remove(at: location.index)
            card.isFaceUp = true
            mixedRun.append(card)
        }
        mixedState.foundations[0] = mixedRun
        XCTAssertNil(payload(for: mixedState).sanitizedForRestore())
    }

    func testRejectsDuplicateCardIDs() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        state.tableau[0][0] = state.tableau[1][0]
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsWrongCardCount() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 9)
        state.tableau[6].removeLast()
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    // MARK: - Helpers

    private func firstLocation(
        where predicate: (Card) -> Bool,
        in tableau: [[Card]]
    ) -> (pile: Int, index: Int)? {
        for pileIndex in tableau.indices {
            if let cardIndex = tableau[pileIndex].firstIndex(where: predicate) {
                return (pileIndex, cardIndex)
            }
        }
        return nil
    }
}
