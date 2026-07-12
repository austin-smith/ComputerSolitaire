import XCTest
@testable import Computer_Solitaire

@MainActor
final class SpiderPersistenceTests: XCTestCase {
    private func payload(for state: GameState) -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: 0,
            stockDrawCount: DrawMode.three.rawValue,
            history: []
        )
    }

    // MARK: - Valid states

    func testFreshDealsRoundTripForEverySuitCount() throws {
        for suitCount in SpiderSuitCount.allCases {
            let state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: suitCount)
            let sanitized = try XCTUnwrap(
                payload(for: state).sanitizedForRestore(),
                "\(suitCount): a fresh deal must pass the validity gate"
            )
            XCTAssertEqual(sanitized.state, state)

            let viewModel = SolitaireViewModel()
            XCTAssertTrue(viewModel.restore(from: sanitized))
            XCTAssertEqual(viewModel.gameVariant, .spider)
            XCTAssertEqual(viewModel.state.spiderSuitCount, suitCount)
        }
    }

    func testMidGameStateWithBankedRunIsValid() {
        // Bank one complete spade run out of a 1-suit deal by hand: the board
        // keeps all 104 cards, so the multiset gate still holds.
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .one)
        var bankedRun: [Card] = []
        for rank in Rank.allCases {
            let location = firstLocation(of: rank, in: state.tableau)!
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
        // Removing scattered cards leaves the stock untouched, so the layout
        // rules (stock in ten-card rows, face-down) still hold.
        XCTAssertNotNil(payload(for: state).sanitizedForRestore())
    }

    // MARK: - Rejected states

    func testRejectsWrongFoundationCount() {
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        state.foundations = Array(repeating: [], count: 4)
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsSingleDeckCardCount() {
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        state.stock.removeLast(50)
        state.tableau[0].removeLast(2)
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsDuplicateCardIDs() {
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        state.tableau[0][0] = state.tableau[1][0]
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsWrongIdentityMultiset() {
        // Swap one spade for an extra copy of a heart: still 104 unique cards,
        // but no Spider deck composes this way.
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        let spadeLocation = firstLocation(where: { $0.suit == .spades }, in: state.tableau)!
        let victim = state.tableau[spadeLocation.pile][spadeLocation.index]
        state.tableau[spadeLocation.pile][spadeLocation.index] = Card(
            suit: .hearts,
            rank: victim.rank,
            isFaceUp: victim.isFaceUp
        )
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsThreeSuitComposition() {
        // Rebuild the deal with a 3-suit multiset: no SpiderSuitCount matches,
        // so the derived difficulty is nil and the state must be rejected.
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .one)
        var toRelabel = 26
        for pileIndex in state.tableau.indices {
            for cardIndex in state.tableau[pileIndex].indices where toRelabel > 0 {
                let card = state.tableau[pileIndex][cardIndex]
                let newSuit: Suit = toRelabel > 13 ? .hearts : .clubs
                state.tableau[pileIndex][cardIndex] = Card(
                    suit: newSuit,
                    rank: card.rank,
                    isFaceUp: card.isFaceUp
                )
                toRelabel -= 1
            }
        }
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsNonEmptyWasteAndOccupiedFreeCell() {
        var wasteState = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        wasteState.waste.append(wasteState.stock.removeLast())
        XCTAssertNil(payload(for: wasteState).sanitizedForRestore())

        var freeCellState = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        freeCellState.freeCells[0] = freeCellState.stock.removeLast()
        XCTAssertNil(payload(for: freeCellState).sanitizedForRestore())
    }

    func testRejectsWrongPileCount() {
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        let removedPile = state.tableau.removeLast()
        state.tableau[0].append(contentsOf: removedPile)
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsPartialStockRow() {
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        var card = state.stock.removeLast()
        card.isFaceUp = true
        state.tableau[0].append(card)
        XCTAssertNil(payload(for: state).sanitizedForRestore(), "The stock only shrinks in ten-card rows")
    }

    func testRejectsFaceUpStockCard() {
        var state = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
        state.stock[0].isFaceUp = true
        XCTAssertNil(payload(for: state).sanitizedForRestore())
    }

    func testRejectsPartialOrMixedFoundationPile() {
        // Move five in-suit cards to a foundation: partial banked runs cannot occur.
        var partialState = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .one)
        var moved: [Card] = []
        for rank in [Rank.ace, .two, .three, .four, .five] {
            let location = firstLocation(of: rank, in: partialState.tableau)!
            moved.append(partialState.tableau[location.pile].remove(at: location.index))
        }
        partialState.foundations[0] = moved
        XCTAssertNil(payload(for: partialState).sanitizedForRestore())

        // A full 13-card foundation pile that mixes suits is equally impossible.
        var mixedState = GameStateFixtures.seededSpiderDeal(seed: 4, suitCount: .two)
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

    func testSanitizationLeavesOtherVariantsUntouched() {
        let klondikeState = GameStateFixtures.validPersistenceState()
        XCTAssertNotNil(payload(for: klondikeState).sanitizedForRestore())
    }

    // MARK: - Helpers

    private func firstLocation(
        of rank: Rank,
        in tableau: [[Card]]
    ) -> (pile: Int, index: Int)? {
        firstLocation(where: { $0.rank == rank }, in: tableau)
    }

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
