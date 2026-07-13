import XCTest
@testable import Computer_Solitaire

@MainActor
final class ScorpionRulesTests: XCTestCase {
    // MARK: - Deal shape and deck composition

    func testNewGameDealShape() {
        let state = GameState.newScorpionGame()

        XCTAssertEqual(state.variant, .scorpion)
        XCTAssertEqual(state.tableau.count, 7)
        XCTAssertEqual(state.tableau.map(\.count), Array(repeating: 7, count: 7))
        for (pileIndex, pile) in state.tableau.enumerated() {
            let faceDownCount = pileIndex < 4 ? 3 : 0
            for (cardIndex, card) in pile.enumerated() {
                XCTAssertEqual(
                    card.isFaceUp,
                    cardIndex >= faceDownCount,
                    "Pile \(pileIndex) hides its bottom \(faceDownCount) cards"
                )
            }
        }
        XCTAssertEqual(state.stock.count, 3)
        XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
        XCTAssertTrue(state.waste.isEmpty)
        XCTAssertEqual(state.wasteDrawCount, 0)
        XCTAssertEqual(state.foundations.count, 4)
        XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
        XCTAssertTrue(state.freeCells.allSatisfy { $0 == nil })

        let allCards = state.stock + state.tableau.joined()
        XCTAssertEqual(allCards.count, 52)
        XCTAssertEqual(Set(allCards.map(\.id)).count, 52, "Every card needs a unique identity")
        XCTAssertEqual(
            Set(allCards.map { CardIdentity(suit: $0.suit, rank: $0.rank) }).count,
            52,
            "The deal uses one standard deck"
        )
    }

    // MARK: - Landing rules

    func testLandingRequiresSameSuitOneRankHigher() {
        let sevenClubs = TestCards.make(.clubs, .seven)
        XCTAssertTrue(
            ScorpionGameRules.canMoveToTableau(
                card: sevenClubs,
                destinationPile: [TestCards.make(.clubs, .eight)]
            )
        )
        XCTAssertFalse(
            ScorpionGameRules.canMoveToTableau(
                card: sevenClubs,
                destinationPile: [TestCards.make(.spades, .eight)]
            ),
            "An off-suit eight must reject the landing"
        )
        XCTAssertFalse(
            ScorpionGameRules.canMoveToTableau(
                card: sevenClubs,
                destinationPile: [TestCards.make(.clubs, .nine)]
            ),
            "The landing must be exactly one rank higher"
        )
        XCTAssertFalse(
            ScorpionGameRules.canMoveToTableau(
                card: sevenClubs,
                destinationPile: [TestCards.make(.clubs, .seven)]
            )
        )
    }

    func testEmptyPileAcceptsOnlyKings() {
        XCTAssertTrue(
            ScorpionGameRules.canMoveToTableau(
                card: TestCards.make(.clubs, .king),
                destinationPile: []
            )
        )
        for rank in Rank.allCases where rank != .king {
            XCTAssertFalse(
                ScorpionGameRules.canMoveToTableau(
                    card: TestCards.make(.clubs, rank),
                    destinationPile: []
                )
            )
        }
    }

    func testNothingLandsOnAnAce() {
        let ace = [TestCards.make(.spades, .ace)]
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                XCTAssertFalse(
                    ScorpionGameRules.canMoveToTableau(
                        card: TestCards.make(suit, rank),
                        destinationPile: ace
                    )
                )
            }
        }
    }

    func testFaceDownTopRejectsLandings() {
        XCTAssertFalse(
            ScorpionGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .seven),
                destinationPile: [TestCards.make(.hearts, .eight, isFaceUp: false)]
            )
        )
    }

    // MARK: - Pickup rules

    func testEveryFaceUpCardIsPickableWithItsCover() {
        // Pile: 9♠ 4♥ 2♣ — thoroughly unordered, yet every face-up card leads a
        // pickable group. That is Scorpion's Yukon-style defining rule.
        let state = ScorpionTestStates.board(
            tableau: [
                [
                    TestCards.make(.spades, .nine),
                    TestCards.make(.hearts, .four),
                    TestCards.make(.clubs, .two)
                ],
                [TestCards.make(.spades, .ten)]
            ]
        )

        let pileZeroSources = AutoMoveAdvisor.candidateSelections(in: state)
            .compactMap { selection -> Int? in
                guard case .tableau(let pile, let index) = selection.source, pile == 0 else {
                    return nil
                }
                return index
            }
        XCTAssertEqual(pileZeroSources.sorted(), [0, 1, 2])
    }

    func testFaceDownCardsAreNotPickable() {
        let state = ScorpionTestStates.board(
            tableau: [
                [
                    TestCards.make(.spades, .nine, isFaceUp: false),
                    TestCards.make(.hearts, .four)
                ]
            ]
        )

        let pileZeroSources = AutoMoveAdvisor.candidateSelections(in: state)
            .compactMap { selection -> Int? in
                guard case .tableau(let pile, let index) = selection.source, pile == 0 else {
                    return nil
                }
                return index
            }
        XCTAssertEqual(pileZeroSources, [1])
    }

    func testUnorderedGroupLandsByItsLeadingCardOnly() {
        // The 9♠-led group is unordered and multi-suit; only the 9♠ must
        // connect, so the 10♠ top is legal and the 10♥ top is not.
        let nineSpades = TestCards.make(.spades, .nine)
        let state = ScorpionTestStates.board(
            tableau: [
                [nineSpades, TestCards.make(.hearts, .four), TestCards.make(.clubs, .two)],
                [TestCards.make(.spades, .ten)],
                [TestCards.make(.hearts, .ten)]
            ]
        )

        let group = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: Array(state.tableau[0])
        )
        XCTAssertEqual(
            AutoMoveAdvisor.legalDestinations(for: group, in: state),
            [.tableau(1)]
        )
    }

    func testFoundationsAreNeverSourcesOrDestinations() {
        let bankedRun = Rank.allCases.map { TestCards.make(.spades, $0) }
        var foundations: [[Card]] = Array(repeating: [], count: 4)
        foundations[0] = bankedRun
        let aceHearts = TestCards.make(.hearts, .ace)
        let state = ScorpionTestStates.board(
            tableau: [[aceHearts]],
            foundations: foundations
        )

        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            if case .foundation = selection.source {
                XCTFail("Scorpion foundations must not be pickup sources")
            }
        }

        let aceSelection = Selection(source: .tableau(pile: 0, index: 0), cards: [aceHearts])
        for destination in AutoMoveAdvisor.legalDestinations(for: aceSelection, in: state) {
            if case .foundation = destination {
                XCTFail("Scorpion foundations must not be legal destinations")
            }
        }
    }

    func testWholePileKingTransferBetweenEmptyColumnsIsRedundantAfterTheDeal() {
        // With the stock spent, every column is interchangeable: a king-led
        // whole pile parked next to empty columns is a no-op relocation, so
        // the advisor refuses it (players still can).
        let kingSpades = TestCards.make(.spades, .king)
        let fourHearts = TestCards.make(.hearts, .four)
        let state = ScorpionTestStates.board(tableau: [[kingSpades, fourHearts]])

        let wholePile = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: [kingSpades, fourHearts]
        )
        XCTAssertTrue(AutoMoveAdvisor.legalDestinations(for: wholePile, in: state).isEmpty)
    }

    func testWholePileKingTransfersTouchingDealColumnsStayAvailableBeforeTheDeal() {
        // While the stock is undealt, each of the first three columns awaits
        // its own dealt card, so relocating a whole king pile out of one (or
        // into one) genuinely changes the position the deal produces. Only
        // transfers between the interchangeable columns 4-7 are no-ops.
        let kingSpades = TestCards.make(.spades, .king)
        let fourHearts = TestCards.make(.hearts, .four)
        let stock = [
            TestCards.make(.hearts, .two, isFaceUp: false),
            TestCards.make(.clubs, .six, isFaceUp: false),
            TestCards.make(.diamonds, .ten, isFaceUp: false)
        ]

        // Whole king pile in a deal-target column: moving it anywhere vacates
        // the column, so every empty column is a meaningful destination.
        let fromDealColumn = ScorpionTestStates.board(
            tableau: [[kingSpades, fourHearts]],
            stock: stock
        )
        let wholePile = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: [kingSpades, fourHearts]
        )
        XCTAssertEqual(
            AutoMoveAdvisor.legalDestinations(for: wholePile, in: fromDealColumn),
            [.tableau(1), .tableau(2), .tableau(3), .tableau(4), .tableau(5), .tableau(6)]
        )

        // Whole king pile outside the deal columns: filling an empty deal
        // column is meaningful, but relocating among columns 4-7 is not.
        let fromInterchangeableColumn = ScorpionTestStates.board(
            tableau: [[], [], [], [], [kingSpades, fourHearts]],
            stock: stock
        )
        let wholePileAtFour = Selection(
            source: .tableau(pile: 4, index: 0),
            cards: [kingSpades, fourHearts]
        )
        XCTAssertEqual(
            AutoMoveAdvisor.legalDestinations(for: wholePileAtFour, in: fromInterchangeableColumn),
            [.tableau(0), .tableau(1), .tableau(2)]
        )
    }

    // MARK: - Run completion

    func testCompletedRunStartIndexFindsOnlyFullKingLedSameSuitRuns() {
        let fullRun = Rank.allCases.reversed().map { TestCards.make(.hearts, $0) }
        XCTAssertEqual(ScorpionGameRules.completedRunStartIndex(in: Array(fullRun)), 0)

        let buried = [TestCards.make(.clubs, .four, isFaceUp: false)] + fullRun
        XCTAssertEqual(ScorpionGameRules.completedRunStartIndex(in: buried), 1)

        let partial = Array(fullRun.dropLast())
        XCTAssertNil(ScorpionGameRules.completedRunStartIndex(in: partial))

        var mixedSuit = Array(fullRun)
        mixedSuit[12] = TestCards.make(.spades, .ace)
        XCTAssertNil(ScorpionGameRules.completedRunStartIndex(in: mixedSuit))
    }

    func testResolveCompletedRunsBanksFlipsAndCascades() {
        // Pile 0 ends in a full heart run over a face-down card; banking must
        // move the run to the first empty foundation (Ace at the bottom), flip
        // the exposed card, and repeat — the flip completes nothing here, but a
        // second pile's full run banks in the same resolution pass.
        let hiddenCard = TestCards.make(.clubs, .four, isFaceUp: false)
        let heartRun = Rank.allCases.reversed().map { TestCards.make(.hearts, $0) }
        let spadeRun = Rank.allCases.reversed().map { TestCards.make(.spades, $0) }
        var state = ScorpionTestStates.board(
            tableau: [[hiddenCard] + heartRun, Array(spadeRun)]
        )

        let resolution = ScorpionGameRules.resolveCompletedRuns(in: &state)

        XCTAssertEqual(resolution.bankedRunCount, 2)
        XCTAssertEqual(
            resolution.revealedCardCount,
            1,
            "The heart run's removal reveals the buried card; the spade run's reveals nothing"
        )
        XCTAssertEqual(state.foundations[0].count, 13)
        XCTAssertEqual(state.foundations[0].first?.rank, .ace)
        XCTAssertEqual(state.foundations[0].last?.rank, .king)
        XCTAssertEqual(state.foundations[1].count, 13)
        XCTAssertEqual(state.tableau[0].map(\.id), [hiddenCard.id])
        XCTAssertTrue(state.tableau[0][0].isFaceUp, "Banking must flip the exposed card")
        XCTAssertTrue(state.tableau[1].isEmpty)
    }

    // MARK: - Stock deal

    func testDealStockPlacesThreeFaceUpCardsOnTheFirstThreePiles() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 6)
        state.tableau[0] = []
        let expectedDealtIDs = Array(state.stock.map(\.id).reversed())

        let resolution = ScorpionGameRules.dealStock(in: &state)

        XCTAssertEqual(resolution, ScorpionGameRules.Resolution())
        XCTAssertTrue(state.stock.isEmpty)
        let dealtByPile = (0..<3).map { state.tableau[$0].last! }
        XCTAssertEqual(dealtByPile.map(\.id), expectedDealtIDs)
        XCTAssertTrue(dealtByPile.allSatisfy(\.isFaceUp))
        XCTAssertEqual(
            state.tableau[0].count,
            1,
            "The deal lands on an empty first pile like any other — it is not a move"
        )
    }

    func testDealStockBanksARunTheDealCompletes() {
        // Pile 0 holds K♥…2♥; the stock's last card is the A♥, dealt onto pile
        // 0 first — completing and banking the run in the same action.
        let heartRunToTwo = Rank.allCases.reversed().dropLast()
            .map { TestCards.make(.hearts, $0) }
        var state = ScorpionTestStates.board(
            tableau: [Array(heartRunToTwo), [TestCards.make(.clubs, .nine)], [TestCards.make(.spades, .four)]],
            stock: [
                TestCards.make(.clubs, .two, isFaceUp: false),
                TestCards.make(.spades, .two, isFaceUp: false),
                TestCards.make(.hearts, .ace, isFaceUp: false)
            ]
        )

        let resolution = ScorpionGameRules.dealStock(in: &state)

        XCTAssertEqual(resolution, ScorpionGameRules.Resolution(bankedRunCount: 1, revealedCardCount: 0))
        XCTAssertEqual(state.foundations[0].count, 13)
        XCTAssertTrue(state.tableau[0].isEmpty)
    }

    func testDealStockIsSingleUse() {
        var state = GameStateFixtures.seededScorpionDeal(seed: 6)
        XCTAssertNotNil(ScorpionGameRules.dealStock(in: &state))

        let stateAfterDeal = state
        XCTAssertNil(ScorpionGameRules.dealStock(in: &state), "An empty stock cannot deal again")
        XCTAssertEqual(state, stateAfterDeal)
    }

    func testCanDealFromStockIgnoresTableauShape() {
        // Unlike Spider, empty piles never block the deal.
        var state = GameStateFixtures.seededScorpionDeal(seed: 6)
        state.tableau[0] = []
        state.tableau[5] = []
        XCTAssertTrue(ScorpionGameRules.canDealFromStock(state: state))

        state.stock = []
        XCTAssertFalse(ScorpionGameRules.canDealFromStock(state: state))
    }

    // MARK: - Session move semantics

    func testSessionMovesUnorderedGroupAndFlipsExposedCard() {
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let nineSpades = TestCards.make(.spades, .nine)
        let fourHearts = TestCards.make(.hearts, .four)
        let tenSpades = TestCards.make(.spades, .ten)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(
            tableau: [[hiddenKing, nineSpades, fourHearts], [tenSpades]]
        )
        viewModel.configureWastelessNewGame()

        XCTAssertTrue(viewModel.canSelectTableauCards([nineSpades, fourHearts]))
        viewModel.selection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [nineSpades, fourHearts]
        )
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))

        XCTAssertEqual(
            viewModel.state.tableau[1].map(\.id),
            [tenSpades.id, nineSpades.id, fourHearts.id]
        )
        XCTAssertEqual(viewModel.state.tableau[0].count, 1)
        XCTAssertTrue(
            viewModel.state.tableau[0][0].isFaceUp,
            "The exposed face-down card should flip when the group leaves"
        )
        XCTAssertEqual(viewModel.movesCount, 1)
    }

    func testSessionRefusesOffSuitDropAndSelfDrop() {
        let nineSpades = TestCards.make(.spades, .nine)
        let tenHearts = TestCards.make(.hearts, .ten)
        let viewModel = SolitaireViewModel()
        viewModel.state = ScorpionTestStates.board(
            tableau: [[nineSpades], [tenHearts]]
        )
        viewModel.configureWastelessNewGame()

        viewModel.selection = Selection(source: .tableau(pile: 0, index: 0), cards: [nineSpades])
        XCTAssertFalse(viewModel.canDrop(to: .tableau(1)), "Off-suit landings are illegal")
        XCTAssertFalse(viewModel.canDrop(to: .tableau(0)), "A self-drop is a cancel, not a move")
    }
}

/// Constructs Scorpion board states for tests: piles are padded to Scorpion's
/// seven columns, foundations to its four banked-run piles.
@MainActor
enum ScorpionTestStates {
    static func board(
        tableau: [[Card]],
        stock: [Card] = [],
        foundations: [[Card]] = Array(repeating: [], count: 4)
    ) -> GameState {
        var paddedTableau = tableau
        while paddedTableau.count < 7 {
            paddedTableau.append([])
        }
        return GameState(
            variant: .scorpion,
            stock: stock,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: foundations,
            tableau: paddedTableau
        )
    }

    /// A seven-pile board with a single face-up spade in every pile, chosen so
    /// no card is another's same-suit successor: no tableau move is legal.
    static func stuckBoard(stock: [Card] = []) -> GameState {
        board(
            tableau: [Rank.ace, .three, .five, .seven, .nine, .jack, .king].map {
                [TestCards.make(.spades, $0)]
            },
            stock: stock
        )
    }
}
