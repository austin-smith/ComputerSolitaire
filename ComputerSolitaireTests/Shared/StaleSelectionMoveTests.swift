import XCTest
@testable import Computer_Solitaire

/// Regression coverage for the duplicate-card corruption: moves apply after an
/// animated drop flight, so a selection queued during that window snapshots the
/// pre-move board — including the in-flight card. Applying such a stale
/// selection used to remove cards by position while appending the snapshot's
/// copies, leaving the same card on the board twice. `tryMoveSelection` now
/// re-derives every selection from the live state and refuses on mismatch.
@MainActor
final class StaleSelectionMoveTests: XCTestCase {
    private func spadeRun(through rank: Rank) -> [Card] {
        Rank.allCases
            .filter { $0 <= rank }
            .map { Card(suit: .spades, rank: $0, isFaceUp: true) }
    }

    private func allBoardCards(in viewModel: SolitaireViewModel) -> [Card] {
        viewModel.state.allCards
    }

    /// The confirmed corruption sequence, driven in the exact order
    /// ContentView does: tap 7♠ (auto-move to foundation queued, flight
    /// starts), tap the 8♥ beneath it during the flight (queues a stale
    /// [8♥, 7♠] stack), land flight one, then process the stale request.
    func testStaleSelectionQueuedDuringDropFlightIsRefused() {
        let viewModel = SolitaireViewModel(variant: .klondike)

        let eightOfHearts = Card(suit: .hearts, rank: .eight, isFaceUp: true)
        let sevenOfSpades = Card(suit: .spades, rank: .seven, isFaceUp: true)
        let nineOfClubs = Card(suit: .clubs, rank: .nine, isFaceUp: true)

        var state = viewModel.state
        state.foundations = [spadeRun(through: .six), [], [], []]
        state.tableau = [
            [eightOfHearts, sevenOfSpades],
            [nineOfClubs],
            [], [], [], [], []
        ]
        state.stock = []
        state.waste = []
        state.wasteDrawCount = 0
        viewModel.state = state

        // Tap 1: queues the 7♠'s auto-move; no model mutation yet.
        viewModel.handleTableauTap(pileIndex: 0, cardIndex: 1)
        guard let firstRequest = viewModel.pendingAutoMove else {
            return XCTFail("expected first auto-move to queue")
        }
        XCTAssertEqual(firstRequest.destination, .foundation(0))

        // ContentView installs the selection and defers handleDrop for the
        // drop flight.
        viewModel.clearPendingAutoMove()
        viewModel.selection = firstRequest.selection
        viewModel.isDragging = true

        // Tap 2 lands mid-flight: the pile still holds the in-flight 7♠, so
        // the queued request snapshots the stale [8♥, 7♠] stack.
        viewModel.handleTableauTap(pileIndex: 0, cardIndex: 0)
        guard let secondRequest = viewModel.pendingAutoMove else {
            return XCTFail("expected second auto-move to queue")
        }
        XCTAssertEqual(secondRequest.destination, .tableau(1))

        // Flight one lands and applies its move.
        XCTAssertTrue(viewModel.handleDrop(to: firstRequest.destination))
        XCTAssertEqual(viewModel.state.foundations[0].last?.id, sevenOfSpades.id)

        // The stale request must be refused at both defense layers: the
        // re-derivation ContentView performs, and the session funnel itself.
        viewModel.clearPendingAutoMove()
        XCTAssertNil(viewModel.liveSelection(matching: secondRequest.selection))
        viewModel.selection = secondRequest.selection
        XCTAssertFalse(viewModel.handleDrop(to: secondRequest.destination))
        XCTAssertNil(viewModel.selection)

        // The board must be untouched by the refused move.
        XCTAssertEqual(viewModel.state.tableau[0].map(\.id), [eightOfHearts.id])
        XCTAssertEqual(viewModel.state.tableau[1].map(\.id), [nineOfClubs.id])
        let allCards = allBoardCards(in: viewModel)
        XCTAssertEqual(allCards.filter { $0.id == sevenOfSpades.id }.count, 1)
        XCTAssertEqual(allCards.filter { $0.id == eightOfHearts.id }.count, 1)
        XCTAssertTrue(viewModel.state.hasNoDuplicateCardIDs)
    }

    /// The waste variant of the race: a waste-top selection held across a
    /// stock draw must not pop the newly drawn card while appending the old
    /// top's copy elsewhere.
    func testWasteSelectionHeldAcrossStockDrawIsRefused() {
        let viewModel = SolitaireViewModel(variant: .klondike)
        viewModel.setStockDrawCount(1)

        let sevenOfSpades = Card(suit: .spades, rank: .seven, isFaceUp: true)
        let queenOfDiamonds = Card(suit: .diamonds, rank: .queen)
        let eightOfHearts = Card(suit: .hearts, rank: .eight, isFaceUp: true)

        var state = viewModel.state
        state.foundations = Array(repeating: [], count: 4)
        state.tableau = [[eightOfHearts], [], [], [], [], [], []]
        state.stock = [queenOfDiamonds]
        state.waste = [sevenOfSpades]
        state.wasteDrawCount = 1
        viewModel.state = state

        // Selection captured from the waste top, then a draw lands beneath it
        // before the deferred move applies.
        viewModel.selection = Selection(source: .waste, cards: [sevenOfSpades])
        viewModel.drawFromStock()
        XCTAssertEqual(viewModel.state.waste.last?.id, queenOfDiamonds.id)

        XCTAssertFalse(viewModel.handleDrop(to: .tableau(0)))

        XCTAssertEqual(
            viewModel.state.waste.map(\.id),
            [sevenOfSpades.id, queenOfDiamonds.id]
        )
        XCTAssertEqual(viewModel.state.tableau[0].map(\.id), [eightOfHearts.id])
        XCTAssertTrue(viewModel.state.hasNoDuplicateCardIDs)
    }

    /// The validation must not get in the way of a normal, up-to-date move.
    func testFreshSelectionStillMoves() {
        let viewModel = SolitaireViewModel(variant: .klondike)

        let eightOfHearts = Card(suit: .hearts, rank: .eight, isFaceUp: true)
        let sevenOfSpades = Card(suit: .spades, rank: .seven, isFaceUp: true)

        var state = viewModel.state
        state.foundations = Array(repeating: [], count: 4)
        state.tableau = [[sevenOfSpades], [eightOfHearts], [], [], [], [], []]
        state.stock = []
        state.waste = []
        state.wasteDrawCount = 0
        viewModel.state = state

        viewModel.selection = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: [sevenOfSpades]
        )
        XCTAssertTrue(viewModel.handleDrop(to: .tableau(1)))
        XCTAssertEqual(
            viewModel.state.tableau[1].map(\.id),
            [eightOfHearts.id, sevenOfSpades.id]
        )
        XCTAssertTrue(viewModel.state.tableau[0].isEmpty)
        XCTAssertTrue(viewModel.state.hasNoDuplicateCardIDs)
    }
}
