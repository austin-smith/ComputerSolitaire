import XCTest
@testable import Computer_Solitaire

/// Covers the fresh-board deal-in flight: the dealer ordering of
/// `newGameDealSequence`, the flight plan's anchors and takeoff budget, and
/// the session's `BoardDealEvent` — published only by fresh deals, never by
/// restores, so a hydrated board can never replay its deal.
@MainActor
final class NewGameDealAnimationTests: XCTestCase {
    // MARK: - Deal sequence ordering

    // Verifies the tableau deals in left-to-right passes: pass one lays each
    // pile's first card, pass two starts at the second pile (pile one holds a
    // single card), like a real dealer.
    func testKlondikeSequenceDealsRowMajor() {
        let state = GameStateFixtures.seededKlondikeDeal(seed: 1)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)

        XCTAssertEqual(sequence.count, 28)
        XCTAssertEqual(
            sequence.prefix(7).map(\.id),
            state.tableau.map { $0[0].id }
        )
        XCTAssertEqual(sequence[7].id, state.tableau[1][1].id)
    }

    func testFreeCellSequenceDealsRowMajor() {
        let state = GameStateFixtures.seededFreeCellDeal(seed: 2)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)

        XCTAssertEqual(sequence.count, 52)
        XCTAssertEqual(
            sequence.prefix(8).map(\.id),
            state.tableau.map { $0[0].id }
        )
    }

    // Verifies Canfield's dealer order: the reserve packet flies only its
    // exposed top card, then the four tableau cards, then the foundation base.
    func testCanfieldSequenceIsReserveTopThenTableauThenFoundationBase() {
        let state = GameStateFixtures.seededCanfieldDeal(seed: 3)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)

        XCTAssertEqual(sequence.count, 6)
        XCTAssertEqual(sequence.first?.id, state.reserve.last?.id)
        XCTAssertEqual(
            sequence[1...4].map(\.id),
            state.tableau.map { $0[0].id }
        )
        XCTAssertEqual(sequence.last?.id, state.foundations[0][0].id)
    }

    // Verifies the starter cards land last: Golf's and TriPeaks' waste card
    // turns over after the board is down.
    func testStarterCardsDealLast() {
        let golf = GameStateFixtures.seededGolfDeal(seed: 4)
        let golfSequence = DealAnimationCoordinator.newGameDealSequence(in: golf)
        XCTAssertEqual(golfSequence.count, 36)
        XCTAssertEqual(golfSequence.last?.id, golf.waste[0].id)

        let triPeaks = GameStateFixtures.seededTriPeaksDeal(seed: 5)
        let triPeaksSequence = DealAnimationCoordinator.newGameDealSequence(in: triPeaks)
        XCTAssertEqual(triPeaksSequence.count, 29)
        XCTAssertEqual(triPeaksSequence.last?.id, triPeaks.waste[0].id)
    }

    func testPyramidSequenceFollowsBoardOrder() {
        let state = GameStateFixtures.seededPyramidDeal(seed: 6)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)

        XCTAssertEqual(sequence.map(\.id), state.pyramid.compactMap { $0?.id })
    }

    // MARK: - Flight plan

    func testPlanFliesFromStockWhenStockFrameExists() {
        let state = GameStateFixtures.seededKlondikeDeal(seed: 7)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)
        let stockFrame = CGRect(x: 10, y: 20, width: 80, height: 112)

        let plan = DealAnimationCoordinator.makeNewGameDealPlan(
            dealtCards: sequence,
            cardFrames: frames(for: sequence),
            stockFrame: stockFrame,
            boardSize: CGSize(width: 800, height: 600)
        )

        XCTAssertEqual(plan?.cards.count, 28)
        XCTAssertEqual(
            plan?.cards.first?.start,
            CGPoint(x: stockFrame.midX, y: stockFrame.midY)
        )
    }

    // Verifies the stockless variants (FreeCell, Yukon) deal from an
    // invisible deck just above the board's top edge.
    func testPlanFallsBackToAboveBoardWhenStockless() {
        let state = GameStateFixtures.seededFreeCellDeal(seed: 8)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)

        let plan = DealAnimationCoordinator.makeNewGameDealPlan(
            dealtCards: sequence,
            cardFrames: frames(for: sequence),
            stockFrame: .zero,
            boardSize: CGSize(width: 800, height: 600)
        )

        XCTAssertEqual(plan?.cards.first?.start, CGPoint(x: 400, y: -112))
    }

    func testPlanRequiresAnAnchor() {
        let state = GameStateFixtures.seededFreeCellDeal(seed: 9)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)

        XCTAssertNil(
            DealAnimationCoordinator.makeNewGameDealPlan(
                dealtCards: sequence,
                cardFrames: frames(for: sequence),
                stockFrame: .zero,
                boardSize: .zero
            )
        )
    }

    func testPlanSkipsCardsWithoutLandingFrames() {
        let state = GameStateFixtures.seededKlondikeDeal(seed: 10)
        let sequence = DealAnimationCoordinator.newGameDealSequence(in: state)
        let framedCards = Array(sequence.dropFirst(3))

        let plan = DealAnimationCoordinator.makeNewGameDealPlan(
            dealtCards: sequence,
            cardFrames: frames(for: framedCards),
            stockFrame: CGRect(x: 0, y: 0, width: 80, height: 112),
            boardSize: CGSize(width: 800, height: 600)
        )

        XCTAssertEqual(plan?.cards.count, sequence.count - 3)
        XCTAssertEqual(plan?.cardIDs, Set(framedCards.map(\.id)))
    }

    // Verifies the takeoff window budget: a big deal compresses its stagger
    // so Spider's 54 cards sweep out in the same window as Klondike's 28,
    // while a small deal keeps the stock flight's relaxed stagger.
    func testPlanBudgetsTakeoffWindow() {
        let spider = GameStateFixtures.seededSpiderDeal(seed: 11, suitCount: .two)
        let spiderSequence = DealAnimationCoordinator.newGameDealSequence(in: spider)
        let spiderPlan = DealAnimationCoordinator.makeNewGameDealPlan(
            dealtCards: spiderSequence,
            cardFrames: frames(for: spiderSequence),
            stockFrame: CGRect(x: 0, y: 0, width: 80, height: 112),
            boardSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(spiderSequence.count, 54)
        XCTAssertEqual(
            spiderPlan?.maxDelay ?? .infinity,
            DealAnimationCoordinator.newGameTakeoffWindow,
            accuracy: 0.001
        )

        let canfield = GameStateFixtures.seededCanfieldDeal(seed: 12)
        let canfieldSequence = DealAnimationCoordinator.newGameDealSequence(in: canfield)
        let canfieldPlan = DealAnimationCoordinator.makeNewGameDealPlan(
            dealtCards: canfieldSequence,
            cardFrames: frames(for: canfieldSequence),
            stockFrame: CGRect(x: 0, y: 0, width: 80, height: 112),
            boardSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(
            canfieldPlan?.maxDelay ?? .infinity,
            DealAnimationCoordinator.staggerInterval * 5,
            accuracy: 0.001
        )
    }

    // MARK: - Board wipe

    // Verifies the palm-stroke physics: the front accelerates (the second
    // half of the stroke covers more ground than the first), a resting card
    // stays planted until the front reaches it, caught cards pile into one
    // clump, and the sweep span carries everything past the right edge.
    func testWipeStrokeCatchesAndClumpsCards() {
        let span: CGFloat = 1000

        let midpoint = BoardWipeCoordinator.frontPosition(progress: 0.5, sweepSpan: span)
        XCTAssertLessThan(midpoint, span / 2)
        XCTAssertEqual(BoardWipeCoordinator.frontPosition(progress: 1, sweepSpan: span), span)

        // Planted until caught: the front at progress 0.3 sits at 90pt, so
        // a card resting at 400pt has not moved yet.
        XCTAssertEqual(
            BoardWipeCoordinator.sweptDisplacement(
                progress: 0.3, startX: 400, rideOffset: 0, sweepSpan: span
            ),
            0
        )

        // Clumping: once caught, two cards from different columns share the
        // same absolute position for the same ride offset.
        let left = BoardWipeCoordinator.sweptDisplacement(
            progress: 0.9, startX: 100, rideOffset: 0, sweepSpan: span
        )
        let right = BoardWipeCoordinator.sweptDisplacement(
            progress: 0.9, startX: 500, rideOffset: 0, sweepSpan: span
        )
        XCTAssertEqual(100 + left, 500 + right)
    }

    func testWipePlanSpansPastTheRightEdge() {
        let state = GameStateFixtures.seededKlondikeDeal(seed: 13)
        let cards = state.tableau.flatMap { $0 }
        let boardSize = CGSize(width: 800, height: 600)
        var frames: [UUID: CGRect] = [:]
        for (pileIndex, pile) in state.tableau.enumerated() {
            for (cardIndex, card) in pile.enumerated() {
                frames[card.id] = CGRect(
                    x: CGFloat(pileIndex) * 110,
                    y: 200 + CGFloat(cardIndex) * 24,
                    width: 80,
                    height: 112
                )
            }
        }

        let plan = BoardWipeCoordinator.makeWipePlan(
            cards: cards,
            cardFrames: frames,
            boardSize: boardSize
        )

        XCTAssertEqual(plan?.cards.count, 28)
        // The stroke must push even the deepest-riding card fully off:
        // at full progress the card's displacement lands it past the edge.
        for item in plan?.cards ?? [] {
            let finalX = item.start.x + BoardWipeCoordinator.sweptDisplacement(
                progress: 1,
                startX: item.start.x,
                rideOffset: item.rideOffset,
                sweepSpan: plan?.sweepSpan ?? 0
            )
            XCTAssertGreaterThan(finalX, boardSize.width + item.size.width / 2)
        }
    }

    func testWipePlanSkipsFramelessCardsAndRequiresABoard() {
        let state = GameStateFixtures.seededKlondikeDeal(seed: 14)
        let cards = state.tableau.flatMap { $0 }

        XCTAssertNil(
            BoardWipeCoordinator.makeWipePlan(
                cards: cards,
                cardFrames: [:],
                boardSize: CGSize(width: 800, height: 600)
            )
        )
        XCTAssertNil(
            BoardWipeCoordinator.makeWipePlan(
                cards: cards,
                cardFrames: frames(for: cards),
                boardSize: .zero
            )
        )

        let framed = Array(cards.prefix(4))
        let plan = BoardWipeCoordinator.makeWipePlan(
            cards: cards,
            cardFrames: frames(for: framed),
            boardSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(plan?.cards.count, 4)
    }

    // MARK: - Session event

    func testFreshDealsPublishBoardDealEvent() {
        SessionTestHarness.withIsolatedStatsStore {
            let viewModel = SessionTestHarness.makeViewModel()
            XCTAssertNil(viewModel.latestBoardDealEvent)

            viewModel.newGame(mode: .klondikeDrawThree)
            let newGameEvent = viewModel.latestBoardDealEvent
            XCTAssertNotNil(newGameEvent)

            viewModel.redeal()
            let redealEvent = viewModel.latestBoardDealEvent
            XCTAssertNotNil(redealEvent)
            XCTAssertNotEqual(newGameEvent, redealEvent)

            viewModel.activateGame(.freecell, restoringFrom: nil)
            XCTAssertNotEqual(viewModel.latestBoardDealEvent, redealEvent)
        }
    }

    func testRestoreClearsBoardDealEvent() {
        SessionTestHarness.withIsolatedStatsStore {
            let source = SessionTestHarness.makeViewModel()
            source.newGame(mode: .klondikeDrawThree)
            let payload = source.persistencePayload()

            let viewModel = SessionTestHarness.makeViewModel()
            viewModel.newGame(mode: .klondikeDrawThree)
            XCTAssertNotNil(viewModel.latestBoardDealEvent)

            XCTAssertTrue(viewModel.activateGame(.klondikeDrawThree, restoringFrom: payload))
            XCTAssertNil(viewModel.latestBoardDealEvent)
        }
    }

    // MARK: - Helpers

    private func frames(for cards: [Card]) -> [UUID: CGRect] {
        cards.enumerated().reduce(into: [:]) { result, item in
            result[item.element.id] = CGRect(
                x: CGFloat(item.offset) * 10,
                y: 200,
                width: 80,
                height: 112
            )
        }
    }

}
