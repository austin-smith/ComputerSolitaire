import XCTest
@testable import Computer_Solitaire

@MainActor
final class PyramidSessionTests: XCTestCase {
    private func makePyramidSession() -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .pyramid)
        viewModel.newGame(mode: .pyramid)
        return viewModel
    }

    func testNewPyramidGameLayout() {
        let state = GameState.newPyramidGame()
        XCTAssertEqual(state.variant, .pyramid)
        XCTAssertEqual(state.pyramid.count, PyramidGeometry.cardCount)
        XCTAssertTrue(state.pyramid.allSatisfy { $0?.isFaceUp == true })
        XCTAssertEqual(state.stock.count, 24)
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertTrue(state.waste.isEmpty)
        XCTAssertTrue(state.tableau.isEmpty)
        XCTAssertTrue(state.discard.isEmpty)
        XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
        XCTAssertEqual(state.wasteRecyclesUsed, 0)
        XCTAssertFalse(state.isWon)
    }

    func testSeededDealMatchesRealDealShape() {
        let real = GameState.newPyramidGame()
        let seeded = GameStateFixtures.seededPyramidDeal(seed: 1)
        XCTAssertEqual(seeded.pyramid.count, real.pyramid.count)
        XCTAssertEqual(seeded.stock.count, real.stock.count)
        XCTAssertEqual(seeded.pyramid.compactMap { $0 }.allSatisfy(\.isFaceUp), true)
        XCTAssertEqual(seeded.tableau, real.tableau)
    }

    func testNewGameConfiguresDrawCounts() {
        let viewModel = makePyramidSession()
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(viewModel.scoringDrawCount, DrawMode.three.rawValue)
        XCTAssertFalse(viewModel.supportsDrawMode)
    }

    func testStockTapDrawsOneCard() {
        let viewModel = makePyramidSession()
        let expectedCard = viewModel.state.stock.last

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.stock.count, 23)
        XCTAssertEqual(viewModel.state.waste.count, 1)
        XCTAssertEqual(viewModel.state.waste.last?.id, expectedCard?.id)
        XCTAssertEqual(viewModel.state.waste.last?.isFaceUp, true)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1)
        XCTAssertEqual(viewModel.visibleWasteCards().count, 1)
        XCTAssertEqual(viewModel.movesCount, 1)
    }

    func testStockRecyclesTwiceThenExhausts() {
        let viewModel = makePyramidSession()

        for pass in 0...2 {
            XCTAssertEqual(viewModel.state.wasteRecyclesUsed, pass)
            while !viewModel.state.stock.isEmpty {
                viewModel.handleStockTap()
            }
            XCTAssertEqual(viewModel.state.waste.count, 24)
            viewModel.handleStockTap()
        }

        // The third pass has been drawn through and no recycles remain: the last
        // tap must not have recycled, and the stock is dead.
        XCTAssertEqual(viewModel.state.wasteRecyclesUsed, 2)
        XCTAssertTrue(viewModel.state.stock.isEmpty)
        XCTAssertEqual(viewModel.state.waste.count, 24)
        XCTAssertFalse(viewModel.canInteractWithStock)
        XCTAssertEqual(viewModel.pyramidWasteRecyclesRemaining, 0)
    }

    func testRecyclePreservesDrawOrder() {
        let viewModel = makePyramidSession()
        var firstPassOrder: [UUID] = []
        while !viewModel.state.stock.isEmpty {
            viewModel.handleStockTap()
            if let top = viewModel.state.waste.last {
                firstPassOrder.append(top.id)
            }
        }
        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.state.wasteRecyclesUsed, 1)

        var secondPassOrder: [UUID] = []
        while !viewModel.state.stock.isEmpty {
            viewModel.handleStockTap()
            if let top = viewModel.state.waste.last {
                secondPassOrder.append(top.id)
            }
        }
        XCTAssertEqual(secondPassOrder, firstPassOrder, "Recycling must preserve draw order")
    }

    func testPairMoveThroughTheSessionScoresAndIsUndoable() {
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.spades, .six)
        let seven = TestCards.make(.hearts, .seven)
        slots[21] = six
        slots[22] = seven
        slots[23] = TestCards.make(.clubs, .two)
        viewModel.state = GameStateFixtures.pyramidState(slots: slots)
        let stateBefore = viewModel.state
        let scoreBefore = viewModel.score

        viewModel.selection = Selection(source: .pyramid(index: 21), cards: [six])
        XCTAssertTrue(viewModel.canDrop(to: .pyramid(22)))
        XCTAssertTrue(viewModel.tryMoveSelection(to: .pyramid(22)))

        XCTAssertNil(viewModel.state.pyramid[21])
        XCTAssertNil(viewModel.state.pyramid[22])
        XCTAssertEqual(viewModel.state.discard.map(\.id), [six.id, seven.id])
        XCTAssertEqual(viewModel.score, scoreBefore + Scoring.delta(for: .removePyramidPair))
        XCTAssertEqual(viewModel.movesCount, 1)
        XCTAssertNil(viewModel.selection)

        viewModel.undo()
        XCTAssertEqual(viewModel.state, stateBefore)
        XCTAssertEqual(viewModel.score, scoreBefore)
    }

    func testKingTapAutoMovesToDiscard() {
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let king = TestCards.make(.diamonds, .king)
        slots[21] = king
        slots[22] = TestCards.make(.clubs, .two)
        viewModel.state = GameStateFixtures.pyramidState(slots: slots)

        viewModel.handlePyramidTap(index: 21)

        guard let pending = viewModel.pendingAutoMove else {
            return XCTFail("Tapping an exposed King should queue its removal")
        }
        XCTAssertEqual(pending.selection.source, .pyramid(index: 21))
        XCTAssertEqual(pending.destination, .discard)
    }

    func testTapSelectThenTapPartnerRemovesThePair() {
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let five = TestCards.make(.spades, .five)
        let eight = TestCards.make(.hearts, .eight)
        let nine = TestCards.make(.clubs, .nine)
        let four = TestCards.make(.diamonds, .four)
        slots[21] = five
        slots[22] = eight
        slots[23] = nine
        slots[24] = four
        viewModel.state = GameStateFixtures.pyramidState(slots: slots)

        // With the 5 selected, tapping the 8 must complete that pair immediately
        // rather than re-resolving the tapped card's own best move.
        viewModel.selection = Selection(source: .pyramid(index: 21), cards: [five])
        viewModel.handlePyramidTap(index: 22)

        XCTAssertNil(viewModel.state.pyramid[21])
        XCTAssertNil(viewModel.state.pyramid[22])
        XCTAssertEqual(Set(viewModel.state.discard.map(\.id)), Set([five.id, eight.id]))
        XCTAssertNotNil(viewModel.state.pyramid[23])
        XCTAssertNotNil(viewModel.state.pyramid[24])
    }

    func testTapSelectThenTapWasteRemovesTheChosenPair() {
        // The waste 7 has two exposed partners; with the higher-slot 6 selected,
        // tapping the waste must remove that chosen pair — not auto-move the
        // waste card onto the other 6 the tap policy would prefer.
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let otherSix = TestCards.make(.spades, .six)
        let chosenSix = TestCards.make(.clubs, .six)
        let wasteSeven = TestCards.make(.diamonds, .seven)
        slots[21] = otherSix
        slots[23] = chosenSix
        viewModel.state = GameStateFixtures.pyramidState(slots: slots, waste: [wasteSeven])

        viewModel.selection = Selection(source: .pyramid(index: 23), cards: [chosenSix])
        viewModel.handleWasteTap()

        XCTAssertNil(viewModel.state.pyramid[23])
        XCTAssertNotNil(viewModel.state.pyramid[21])
        XCTAssertTrue(viewModel.state.waste.isEmpty)
        XCTAssertEqual(Set(viewModel.state.discard.map(\.id)), Set([chosenSix.id, wasteSeven.id]))
        XCTAssertNil(viewModel.pendingAutoMove)
    }

    func testTappingCoveredCardClearsSelection() {
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .eight)
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .nine)
        viewModel.state = GameStateFixtures.pyramidState(slots: slots)

        viewModel.selection = Selection(source: .pyramid(index: 21), cards: [slots[21]!])
        viewModel.handlePyramidTap(index: 15)

        XCTAssertNil(viewModel.selection)
        XCTAssertNotNil(viewModel.state.pyramid[15])
    }

    func testWasteKingIsRemovableThroughTheSession() {
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        let king = TestCards.make(.diamonds, .king)
        viewModel.state = GameStateFixtures.pyramidState(slots: slots, waste: [king])
        let scoreBefore = viewModel.score

        viewModel.selection = Selection(source: .waste, cards: [king])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .discard))

        XCTAssertTrue(viewModel.state.waste.isEmpty)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 0)
        XCTAssertEqual(viewModel.state.discard.last?.id, king.id)
        XCTAssertEqual(viewModel.score, scoreBefore + Scoring.delta(for: .removePyramidKing))
    }

    func testWinRequiresOnlyTheClearedPyramid() {
        let viewModel = makePyramidSession()
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.spades, .six)
        let seven = TestCards.make(.hearts, .seven)
        slots[21] = six
        slots[22] = seven
        viewModel.state = GameStateFixtures.pyramidState(
            slots: slots,
            stock: [TestCards.make(.clubs, .two), TestCards.make(.clubs, .three)],
            fillDiscardFromRemainder: true
        )
        XCTAssertFalse(viewModel.isWin)

        viewModel.selection = Selection(source: .pyramid(index: 21), cards: [six])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .pyramid(22)))

        XCTAssertTrue(viewModel.isWin, "Clearing the pyramid wins even with stock cards left")
        XCTAssertFalse(viewModel.state.stock.isEmpty)
    }

    func testUndoRestoresDrawAndRecycle() {
        let viewModel = makePyramidSession()

        let freshState = viewModel.state
        viewModel.handleStockTap()
        viewModel.undo()
        XCTAssertEqual(viewModel.state, freshState)

        while !viewModel.state.stock.isEmpty {
            viewModel.handleStockTap()
        }
        let drawnOutState = viewModel.state
        viewModel.handleStockTap()
        XCTAssertEqual(viewModel.state.wasteRecyclesUsed, 1)
        viewModel.undo()
        XCTAssertEqual(viewModel.state, drawnOutState)
        XCTAssertEqual(viewModel.state.wasteRecyclesUsed, 0)
    }

    func testHintAvailabilityTracksStockAndRecycles() {
        let viewModel = makePyramidSession()
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: viewModel.state))

        // A dead board: no pairs, no stock, no waste, no recycles left.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .nine)
        let deadState = GameStateFixtures.pyramidState(slots: slots, passesUsed: 2)
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: deadState))

        // The same board with a recycle left keeps the button alive.
        let liveState = GameStateFixtures.pyramidState(
            slots: slots,
            waste: [TestCards.make(.clubs, .two)],
            passesUsed: 1
        )
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: liveState))
    }
}
