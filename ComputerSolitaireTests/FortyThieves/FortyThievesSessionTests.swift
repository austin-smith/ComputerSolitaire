import XCTest
@testable import Computer_Solitaire

@MainActor
final class FortyThievesSessionTests: XCTestCase {
    private func makeSession() -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .fortyThieves)
        viewModel.newGame(mode: .fortyThieves)
        return viewModel
    }

    /// A session staged on a hand-constructed board; draw counts configured
    /// as a real Forty Thieves game would be.
    private func makeStagedSession(state: GameState) -> SolitaireViewModel {
        let viewModel = SolitaireViewModel(variant: .fortyThieves)
        viewModel.state = state
        viewModel.configureFortyThievesNewGame()
        viewModel.setWasteDrawCount(min(1, state.waste.count))
        return viewModel
    }

    func testNewGameDealsFortyFaceUpCardsAndConfiguresDrawCounts() {
        let viewModel = makeSession()
        let state = viewModel.state

        XCTAssertEqual(state.tableau.count, FortyThievesGameRules.columnCount)
        XCTAssertTrue(state.tableau.allSatisfy { $0.count == FortyThievesGameRules.dealColumnDepth })
        XCTAssertTrue(state.tableau.allSatisfy { $0.allSatisfy(\.isFaceUp) })
        XCTAssertEqual(state.stock.count, FortyThievesGameRules.dealStockCardCount)
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertTrue(state.waste.isEmpty)
        XCTAssertEqual(state.wasteDrawCount, 0)
        XCTAssertEqual(state.foundations.count, 8)
        XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
        XCTAssertNotNil(
            SavedGamePayload(state: state, movesCount: 0, score: 0, stockDrawCount: DrawMode.one.rawValue, history: [])
                .sanitizedForRestore(at: DateFixtures.reference)
        )

        XCTAssertEqual(viewModel.stockDrawCount, DrawMode.one.rawValue)
        XCTAssertEqual(viewModel.scoringDrawCount, DrawMode.three.rawValue)
        XCTAssertFalse(viewModel.supportsDrawMode)
    }

    func testSeededDealMatchesRealDealShape() {
        let real = GameState.newFortyThievesGame()
        let seeded = GameStateFixtures.seededFortyThievesDeal(seed: 1)
        XCTAssertEqual(seeded.tableau.count, real.tableau.count)
        XCTAssertEqual(seeded.tableau.map(\.count), real.tableau.map(\.count))
        XCTAssertEqual(seeded.stock.count, real.stock.count)
        XCTAssertEqual(seeded.waste.count, real.waste.count)
        XCTAssertEqual(seeded.foundations.count, real.foundations.count)
        XCTAssertNotNil(
            SavedGamePayload(state: seeded, movesCount: 0, score: 0, stockDrawCount: DrawMode.one.rawValue, history: [])
                .sanitizedForRestore(at: DateFixtures.reference)
        )
    }

    func testStockTapTurnsExactlyOneCardOntoTheWaste() {
        let viewModel = makeSession()
        let expectedCard = viewModel.state.stock.last

        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state.stock.count, 63)
        XCTAssertEqual(viewModel.state.waste.count, 1)
        XCTAssertEqual(viewModel.state.waste.last?.id, expectedCard?.id)
        XCTAssertEqual(viewModel.state.waste.last?.isFaceUp, true)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1)
        XCTAssertEqual(viewModel.movesCount, 1)
    }

    func testEmptyStockTapIsANoOpWithNoRecycle() {
        let viewModel = makeStagedSession(
            state: GameStateFixtures.fortyThievesState(
                columns: [[TestCards.make(.spades, .eight)]],
                waste: [TestCards.make(.hearts, .three), TestCards.make(.clubs, .ten)]
            )
        )
        let before = viewModel.state

        XCTAssertFalse(viewModel.canInteractWithStock)
        viewModel.handleStockTap()

        XCTAssertEqual(viewModel.state, before, "The single pass never recycles the waste")
        XCTAssertEqual(viewModel.movesCount, 0)
        XCTAssertNil(viewModel.peekUndoSnapshot())
    }

    func testPlayingTheWasteTopExposesTheNextWasteCard() {
        let buried = TestCards.make(.hearts, .three)
        let top = TestCards.make(.spades, .seven)
        let viewModel = makeStagedSession(
            state: GameStateFixtures.fortyThievesState(
                columns: [[TestCards.make(.spades, .eight)]],
                waste: [buried, top]
            )
        )

        viewModel.selection = Selection(source: .waste, cards: [viewModel.state.waste[1]])
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(0)))

        XCTAssertEqual(viewModel.state.tableau[0].last?.id, top.id)
        XCTAssertEqual(viewModel.state.waste.map(\.id), [buried.id])
        XCTAssertEqual(viewModel.state.wasteDrawCount, 1)
        TestAssertions.assertSingleVisibleWasteCard(viewModel, expected: buried)
    }

    func testMoveScoringMatchesTheClassicSchedule() {
        func score(
            afterMoving source: Selection.Source,
            to destination: Destination,
            in state: GameState
        ) -> Int {
            let viewModel = makeStagedSession(state: state)
            let cards: [Card]
            switch source {
            case .waste:
                cards = [state.waste[state.waste.count - 1]]
            case .tableau(let pile, let index):
                cards = [state.tableau[pile][index]]
            default:
                XCTFail("Unsupported source")
                return 0
            }
            viewModel.selection = Selection(source: source, cards: cards)
            XCTAssertTrue(viewModel.tryMoveSelection(to: destination))
            return viewModel.score
        }

        let wastePlayState = GameStateFixtures.fortyThievesState(
            columns: [[TestCards.make(.spades, .eight)]],
            waste: [TestCards.make(.spades, .seven)]
        )
        XCTAssertEqual(score(afterMoving: .waste, to: .tableau(0), in: wastePlayState), 5)

        let wasteBankState = GameStateFixtures.fortyThievesState(
            columns: [[TestCards.make(.spades, .eight)]],
            waste: [TestCards.make(.hearts, .ace)]
        )
        XCTAssertEqual(score(afterMoving: .waste, to: .foundation(0), in: wasteBankState), 10)

        let tableauBankState = GameStateFixtures.fortyThievesState(
            columns: [[TestCards.make(.hearts, .ace)]]
        )
        XCTAssertEqual(
            score(
                afterMoving: .tableau(pile: 0, index: 0),
                to: .foundation(0),
                in: tableauBankState
            ),
            10
        )

        let tableauBuildState = GameStateFixtures.fortyThievesState(
            columns: [
                [TestCards.make(.hearts, .four), TestCards.make(.spades, .seven)],
                [TestCards.make(.spades, .eight)]
            ]
        )
        XCTAssertEqual(
            score(
                afterMoving: .tableau(pile: 0, index: 1),
                to: .tableau(1),
                in: tableauBuildState
            ),
            0,
            "Tableau-to-tableau moves score nothing"
        )
    }

    // MARK: - Auto-finish

    /// All eight foundations built through Queen; the eight Kings split
    /// between tableau tops and the waste.
    private func nearWonState(kingsInWaste: Int) -> GameState {
        let foundations = Suit.allCases.flatMap { suit in
            (0..<2).map { _ in
                Rank.allCases.filter { $0 != .king }.map { TestCards.make(suit, $0) }
            }
        }
        var kings = Suit.allCases.flatMap { suit in
            [TestCards.make(suit, .king), TestCards.make(suit, .king)]
        }
        var waste: [Card] = []
        for _ in 0..<kingsInWaste {
            waste.append(kings.removeLast())
        }
        return GameStateFixtures.fortyThievesState(
            columns: kings.map { [$0] },
            waste: waste,
            foundations: foundations
        )
    }

    func testAutoFinishFiresOnceStockIsEmptyAndPlaysTheWasteToo() {
        let viewModel = makeStagedSession(state: nearWonState(kingsInWaste: 2))
        viewModel.refreshAutoFinishAvailability()
        XCTAssertTrue(viewModel.isAutoFinishAvailable)

        var steps = 0
        while !viewModel.state.isWon, steps < 20 {
            guard let move = AutoFinishPlanner.nextAutoFinishMove(in: viewModel.state) else {
                return XCTFail("Auto-finish ran out of moves before winning")
            }
            viewModel.selection = move.selection
            XCTAssertTrue(viewModel.tryMoveSelection(to: move.destination))
            steps += 1
        }
        XCTAssertTrue(viewModel.state.isWon)
    }

    func testAutoFinishIsUnavailableWhileStockRemains() {
        var state = nearWonState(kingsInWaste: 0)
        var buried = state.tableau[0].removeLast()
        buried.isFaceUp = false
        state.stock = [buried]

        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testAutoFinishIsUnavailableWhenTheGreedyRunStalls() {
        // One spade foundation is complete and the other stops at Jack; its
        // Queen is buried under the second King of spades, which no foundation
        // can accept — the greedy run banks the other kings and stalls.
        var foundations: [[Card]] = [
            Rank.allCases.map { TestCards.make(.spades, $0) },
            Rank.allCases.filter { $0.rawValue <= 11 }.map { TestCards.make(.spades, $0) }
        ]
        for suit in Suit.allCases where suit != .spades {
            let throughQueen = Rank.allCases.filter { $0 != .king }.map { TestCards.make(suit, $0) }
            foundations.append(throughQueen)
            foundations.append(throughQueen.map { TestCards.make($0.suit, $0.rank) })
        }
        var columns: [[Card]] = [
            [TestCards.make(.spades, .queen), TestCards.make(.spades, .king)]
        ]
        for suit in Suit.allCases where suit != .spades {
            columns.append([TestCards.make(suit, .king)])
            columns.append([TestCards.make(suit, .king)])
        }
        let state = GameStateFixtures.fortyThievesState(columns: columns, foundations: foundations)

        XCTAssertNotNil(
            SavedGamePayload(state: state, movesCount: 0, score: 0, stockDrawCount: DrawMode.one.rawValue, history: [])
                .sanitizedForRestore(at: DateFixtures.reference),
            "The stall must be a legal 104-card position"
        )
        XCTAssertFalse(AutoFinishPlanner.canAutoFinish(in: state))
    }

    func testWinningAppliesTheTimeBonusOnce() {
        let dateProvider = TestDateProvider(now: DateFixtures.reference)
        let viewModel = SolitaireViewModel(dateProvider: dateProvider, variant: .fortyThieves)
        viewModel.state = nearWonState(kingsInWaste: 0)
        viewModel.configureFortyThievesNewGame()
        for pile in 0..<8 {
            let king = viewModel.state.tableau[pile][0]
            viewModel.selection = Selection(
                source: .tableau(pile: pile, index: 0),
                cards: [king]
            )
            guard let destination = viewModel.state.foundations.indices.first(where: { index in
                GameRules.canMoveToFoundation(card: king, foundation: viewModel.state.foundations[index])
            }) else {
                return XCTFail("No foundation accepts the king")
            }
            XCTAssertTrue(viewModel.tryMoveSelection(to: .foundation(destination)))
        }

        XCTAssertTrue(viewModel.isWin)
        XCTAssertNotNil(viewModel.finalElapsedSeconds)
        // Eight banks at +10 plus the full draw-three time bonus (no time
        // elapsed under the fixed clock).
        XCTAssertEqual(viewModel.score, 80 + Scoring.timedMaxBonusDrawThree)
        XCTAssertEqual(viewModel.displayScore(at: DateFixtures.plus(60)), viewModel.score)
    }

    // MARK: - Hints and loss detection

    /// No same-suit adjacency anywhere, no empty column, no waste, and empty
    /// foundations: nothing plays.
    private func deadBoardColumns() -> [[Card]] {
        var columns = Suit.allCases.flatMap { suit in
            [
                [TestCards.make(.hearts, .queen), TestCards.make(suit, .three)],
                [TestCards.make(.clubs, .queen), TestCards.make(suit, .three)]
            ]
        }
        columns.append([TestCards.make(.hearts, .queen), TestCards.make(.spades, .eight)])
        columns.append([TestCards.make(.clubs, .queen), TestCards.make(.spades, .eight)])
        return columns
    }

    func testAnyPlayerMoveExistsWhileStockRemains() {
        let state = GameStateFixtures.fortyThievesState(
            columns: deadBoardColumns(),
            stock: [TestCards.make(.diamonds, .king)]
        )
        XCTAssertTrue(HintAdvisor.anyPlayerMoveExists(in: state), "A draw is always a legal action")
    }

    func testDeadPositionReportsNoMoves() {
        let state = GameStateFixtures.fortyThievesState(columns: deadBoardColumns())
        XCTAssertFalse(HintAdvisor.anyPlayerMoveExists(in: state))
    }

    // MARK: - Redeal

    func testRedealRestoresTheIdenticalDeal() {
        let viewModel = makeSession()
        let initialState = viewModel.state

        viewModel.handleStockTap()
        viewModel.handleStockTap()
        XCTAssertNotEqual(viewModel.state, initialState)

        viewModel.redeal()

        XCTAssertEqual(viewModel.state, initialState)
        XCTAssertEqual(viewModel.movesCount, 0)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertEqual(viewModel.state.wasteDrawCount, 0)
    }
}
