import XCTest
@testable import Computer_Solitaire

@MainActor
final class CanfieldSessionTests: XCTestCase {
    private func makeViewModel(state: GameState? = nil) -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .canfield)
        if let state {
            viewModel.state = state
        }
        return viewModel
    }

    // MARK: - Deal

    func testNewGameDealsTheCanfieldLayout() {
        let state = GameState.newCanfieldGame()

        XCTAssertEqual(state.variant, .canfield)
        XCTAssertEqual(state.reserve.count, CanfieldGameRules.reserveCardCount)
        XCTAssertEqual(
            state.reserve.filter(\.isFaceUp).count,
            1,
            "Exactly the reserve top deals face up"
        )
        XCTAssertEqual(state.reserve.last?.isFaceUp, true)
        XCTAssertEqual(state.foundations.count, 4)
        XCTAssertEqual(state.foundations[0].count, 1, "The base card seeds the first foundation")
        XCTAssertEqual(state.foundations[0].first?.isFaceUp, true)
        XCTAssertTrue(state.foundations[1...].allSatisfy(\.isEmpty))
        XCTAssertEqual(state.tableau.count, CanfieldGameRules.tableauPileCount)
        XCTAssertTrue(state.tableau.allSatisfy { $0.count == 1 && $0[0].isFaceUp })
        XCTAssertEqual(state.stock.count, CanfieldGameRules.dealStockCardCount)
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertTrue(state.waste.isEmpty)
    }

    func testNewGameConfiguresDrawThree() {
        let viewModel = makeViewModel()
        viewModel.newGame(mode: .canfield)
        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.three.rawValue)
        XCTAssertEqual(viewModel.gameMode, .canfield)
    }

    // MARK: - Stock and recycling

    func testStockTapTurnsThreeCardsPreservingOrder() {
        let viewModel = makeViewModel()
        viewModel.newGame(mode: .canfield)
        let expected = Array(viewModel.state.stock.suffix(3)).reversed().map(\.id)

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.waste.suffix(3).map(\.id), Array(expected))
        XCTAssertEqual(viewModel.state.wasteDrawCount, 3)
        XCTAssertEqual(viewModel.visibleWasteCards().count, 3)
    }

    func testStockTapTurnsTheRemainderWhenFewerThanThreeRemain() {
        var state = GameStateFixtures.seededCanfieldDeal(seed: 7)
        let leftover = Array(state.stock.suffix(2))
        state.waste = Array(state.stock.dropLast(2)).map { card in
            var faceUp = card
            faceUp.isFaceUp = true
            return faceUp
        }
        state.stock = leftover
        state.wasteDrawCount = min(3, state.waste.count)
        let viewModel = makeViewModel(state: state)

        viewModel.handleStockTap()

        XCTAssertTrue(viewModel.state.stock.isEmpty)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 2)
    }

    func testTapOnSpentStockRecyclesTheWasteWithoutPenalty() {
        var state = GameStateFixtures.seededCanfieldDeal(seed: 3)
        state.waste = state.stock.reversed().map { card in
            var faceUp = card
            faceUp.isFaceUp = true
            return faceUp
        }
        state.stock = []
        state.wasteDrawCount = 3
        let viewModel = makeViewModel(state: state)
        let wasteOrder = viewModel.state.waste.map(\.id)
        let scoreBefore = viewModel.score

        viewModel.handleStockTap()

        XCTAssertTrue(viewModel.state.waste.isEmpty)
        XCTAssertEqual(
            viewModel.state.stock.map(\.id),
            wasteOrder.reversed(),
            "The waste turns over as-is to form the new stock"
        )
        XCTAssertTrue(viewModel.state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertEqual(viewModel.score, scoreBefore, "Canfield redeals are free and unlimited")
        XCTAssertTrue(viewModel.canInteractWithStock, "Redeals are unlimited")
    }

    // MARK: - Moves and effects

    func testFoundationMoveFromTableauTriggersTheReserveFill() throws {
        let reserveTop = TestCards.make(.diamonds, .queen)
        let baseCard = TestCards.make(.spades, .five)
        let movingCard = TestCards.make(.hearts, .five)
        let state = GameStateFixtures.canfieldState(
            columns: [[movingCard]],
            reserve: [TestCards.make(.clubs, .nine), reserveTop],
            foundations: [[baseCard]],
            fillStockFromRemainder: true
        )
        let viewModel = makeViewModel(state: state)
        viewModel.selectFromTableau(pileIndex: 0, cardIndex: 0)

        XCTAssertTrue(viewModel.tryMoveSelection(to: .foundation(1)))
        XCTAssertEqual(viewModel.state.foundations[1].first?.id, movingCard.id)
        XCTAssertEqual(
            viewModel.state.tableau[0].first?.id,
            reserveTop.id,
            "The emptied pile refills from the reserve at once"
        )
        XCTAssertEqual(viewModel.state.reserve.count, 1)
        XCTAssertEqual(viewModel.state.reserve.last?.isFaceUp, true)
        XCTAssertEqual(
            viewModel.score,
            Scoring.delta(for: .tableauToFoundation) + Scoring.delta(for: .reserveToTableau),
            "The compulsory fill scores like any reserve-to-tableau play"
        )
    }

    func testReserveMovesScore() {
        let reserveTop = TestCards.make(.hearts, .five)
        let state = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.spades, .six)]],
            reserve: [TestCards.make(.clubs, .nine), reserveTop],
            foundations: [[TestCards.make(.spades, .five)]],
            fillStockFromRemainder: true
        )

        // Reserve to foundation.
        var viewModel = makeViewModel(state: state)
        viewModel.selection = Selection(source: .reserve, cards: [reserveTop])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .foundation(1)))
        XCTAssertEqual(viewModel.score, Scoring.delta(for: .reserveToFoundation))

        // Reserve to tableau.
        viewModel = makeViewModel(state: state)
        viewModel.selection = Selection(source: .reserve, cards: [reserveTop])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))
        XCTAssertEqual(viewModel.score, Scoring.delta(for: .reserveToTableau))
        XCTAssertEqual(viewModel.state.reserve.count, 1)
        XCTAssertEqual(viewModel.state.reserve.last?.isFaceUp, true)
    }

    func testReserveDragStartsOnlyWithACardToGive() {
        let withReserve = makeViewModel(
            state: GameStateFixtures.canfieldState(
                columns: [[TestCards.make(.spades, .six)]],
                reserve: [TestCards.make(.hearts, .five)],
                foundations: [[TestCards.make(.spades, .five)]],
                fillStockFromRemainder: true
            )
        )
        XCTAssertTrue(withReserve.startDragFromReserve())
        XCTAssertEqual(withReserve.selection?.source, .reserve)

        let emptyReserve = makeViewModel(
            state: GameStateFixtures.canfieldState(
                columns: [[TestCards.make(.spades, .six)]],
                foundations: [[TestCards.make(.spades, .five)]],
                fillStockFromRemainder: true
            )
        )
        XCTAssertFalse(emptyReserve.startDragFromReserve())
    }

    func testSpentFanUncoversThePreviousWasteCard() {
        // Play every card of the current three-card turn: the card beneath —
        // dealt on an earlier turn — becomes the waste top, and it must stay
        // visible and playable. Burying it until the next stock action would
        // break Canfield's "top waste card is always available" rule.
        let buried = TestCards.make(.clubs, .nine)
        let fanned = TestCards.make(.hearts, .five)
        let state = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.spades, .six)]],
            waste: [buried, fanned],
            foundations: [[TestCards.make(.diamonds, .ten)]],
            wasteDrawCount: 1,
            fillStockFromRemainder: true
        )
        let viewModel = makeViewModel(state: state)
        viewModel.selection = Selection(source: .waste, cards: [fanned])

        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1, "The fan floors at one, not zero")
        XCTAssertEqual(viewModel.visibleWasteCards().map(\.id), [buried.id])

        let wasteSelections = AutoMoveAdvisor.candidateSelections(in: viewModel.state)
            .filter { $0.source == .waste }
        XCTAssertEqual(wasteSelections.first?.cards.first?.id, buried.id)
        XCTAssertTrue(viewModel.startDragFromWaste())
    }

    func testWasteMoveScoresAndDecrementsTheFan() {
        let wastePlay = TestCards.make(.hearts, .five)
        let state = GameStateFixtures.canfieldState(
            columns: [[TestCards.make(.spades, .six)]],
            waste: [TestCards.make(.clubs, .nine), wastePlay],
            foundations: [[TestCards.make(.diamonds, .ten)]],
            wasteDrawCount: 2,
            fillStockFromRemainder: true
        )
        let viewModel = makeViewModel(state: state)
        viewModel.selection = Selection(source: .waste, cards: [wastePlay])

        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))
        XCTAssertEqual(viewModel.score, Scoring.delta(for: .wasteToTableau))
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1)
    }

    // MARK: - Win and auto-finish

    func testAllFoundationsFullIsAWin() {
        var foundations: [[Card]] = []
        let base = Rank.nine
        for suit in Suit.allCases {
            var pile: [Card] = []
            for offset in 0..<Rank.allCases.count {
                let rawValue = (base.rawValue - 1 + offset) % Rank.allCases.count + 1
                pile.append(TestCards.make(suit, Rank(rawValue: rawValue) ?? .ace))
            }
            foundations.append(pile)
        }
        let state = GameStateFixtures.canfieldState(columns: [], foundations: foundations)
        XCTAssertTrue(state.isWon)
    }

    func testAutoFinishRequiresASpentStockAndWaste() {
        let base = Rank.five
        var foundations: [[Card]] = []
        for suit in Suit.allCases {
            var pile: [Card] = []
            for offset in 0..<(Rank.allCases.count - 1) {
                let rawValue = (base.rawValue - 1 + offset) % Rank.allCases.count + 1
                pile.append(TestCards.make(suit, Rank(rawValue: rawValue) ?? .ace))
            }
            foundations.append(pile)
        }
        // Each suit's last card (offset twelve = base minus one) waits on a
        // tableau pile; the wrap-aware greedy run must bank all four.
        let lastRankValue = (base.rawValue - 2 + Rank.allCases.count) % Rank.allCases.count + 1
        let lastRank = Rank(rawValue: lastRankValue) ?? .ace
        let columns = Suit.allCases.map { suit in
            [TestCards.make(suit, lastRank)]
        }
        let ready = GameStateFixtures.canfieldState(columns: columns, foundations: foundations)
        XCTAssertTrue(AutoFinishPlanner.canAutoFinish(in: ready))

        var withStock = ready
        withStock.stock = [TestCards.make(.spades, .four, isFaceUp: false)]
        withStock.tableau[0] = []
        XCTAssertFalse(
            AutoFinishPlanner.canAutoFinish(in: withStock),
            "A live stock keeps the ending an open choice"
        )
    }
}
