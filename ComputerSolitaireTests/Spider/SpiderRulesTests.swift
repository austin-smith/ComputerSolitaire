import XCTest
@testable import Computer_Solitaire

@MainActor
final class SpiderRulesTests: XCTestCase {
    // MARK: - Deal shape and deck composition

    func testNewGameDealShape() {
        for suitCount in SpiderSuitCount.allCases {
            let state = GameState.newSpiderGame(suitCount: suitCount)

            XCTAssertEqual(state.variant, .spider)
            XCTAssertEqual(state.tableau.count, 10)
            XCTAssertEqual(state.tableau.map(\.count), [6, 6, 6, 6, 5, 5, 5, 5, 5, 5])
            for pile in state.tableau {
                for (index, card) in pile.enumerated() {
                    XCTAssertEqual(
                        card.isFaceUp,
                        index == pile.count - 1,
                        "Only each pile's top card should be dealt face up"
                    )
                }
            }
            XCTAssertEqual(state.stock.count, 50)
            XCTAssertTrue(state.stock.allSatisfy { !$0.isFaceUp })
            XCTAssertTrue(state.waste.isEmpty)
            XCTAssertEqual(state.wasteDrawCount, 0)
            XCTAssertEqual(state.foundations.count, 8)
            XCTAssertTrue(state.foundations.allSatisfy(\.isEmpty))
            XCTAssertTrue(state.freeCells.allSatisfy { $0 == nil })
        }
    }

    func testDeckCompositionPerSuitCount() {
        let expectedSuits: [SpiderSuitCount: Set<Suit>] = [
            .one: [.spades],
            .two: [.spades, .hearts],
            .four: Set(Suit.allCases)
        ]
        for suitCount in SpiderSuitCount.allCases {
            let deck = SpiderDeck.deck(suitCount: suitCount)
            XCTAssertEqual(deck.count, 104)
            XCTAssertEqual(Set(deck.map(\.id)).count, 104, "Every card needs a unique identity")
            XCTAssertEqual(Set(deck.map(\.suit)), expectedSuits[suitCount])

            let copiesPerIdentity = 104 / (suitCount.rawValue * Rank.allCases.count)
            var counts: [CardIdentity: Int] = [:]
            for card in deck {
                counts[CardIdentity(suit: card.suit, rank: card.rank), default: 0] += 1
            }
            XCTAssertTrue(
                counts.values.allSatisfy { $0 == copiesPerIdentity },
                "\(suitCount): every rank of every composed suit appears \(copiesPerIdentity) times"
            )
            XCTAssertEqual(counts, SpiderDeck.expectedIdentityCounts(suitCount: suitCount))
        }
    }

    func testSuitCountIsDerivedFromTheCardsInPlay() {
        for suitCount in SpiderSuitCount.allCases {
            let state = GameStateFixtures.seededSpiderDeal(seed: 3, suitCount: suitCount)
            XCTAssertEqual(state.spiderSuitCount, suitCount)
        }
        XCTAssertNil(GameStateFixtures.seededYukonDeal(seed: 3).spiderSuitCount)
    }

    // MARK: - Landing rules

    func testSingleCardLandsOnAnySuitOneRankHigher() {
        let sevenHearts = TestCards.make(.hearts, .seven)
        XCTAssertTrue(
            SpiderGameRules.canMoveToTableau(
                card: sevenHearts,
                destinationPile: [TestCards.make(.spades, .eight)]
            ),
            "Suit must not matter for a landing"
        )
        XCTAssertTrue(
            SpiderGameRules.canMoveToTableau(
                card: sevenHearts,
                destinationPile: [TestCards.make(.hearts, .eight)]
            )
        )
        XCTAssertFalse(
            SpiderGameRules.canMoveToTableau(
                card: sevenHearts,
                destinationPile: [TestCards.make(.spades, .nine)]
            ),
            "The landing must be exactly one rank higher"
        )
        XCTAssertFalse(
            SpiderGameRules.canMoveToTableau(
                card: sevenHearts,
                destinationPile: [TestCards.make(.spades, .seven)]
            )
        )
    }

    func testEmptyPileAcceptsAnyCard() {
        for rank in [Rank.ace, .seven, .king] {
            XCTAssertTrue(
                SpiderGameRules.canMoveToTableau(
                    card: TestCards.make(.clubs, rank),
                    destinationPile: []
                )
            )
        }
    }

    func testNothingLandsOnAnAce() {
        let ace = [TestCards.make(.spades, .ace)]
        for rank in Rank.allCases {
            XCTAssertFalse(
                SpiderGameRules.canMoveToTableau(
                    card: TestCards.make(.hearts, rank),
                    destinationPile: ace
                )
            )
        }
    }

    func testFaceDownTopRejectsLandings() {
        XCTAssertFalse(
            SpiderGameRules.canMoveToTableau(
                card: TestCards.make(.hearts, .seven),
                destinationPile: [TestCards.make(.spades, .eight, isFaceUp: false)]
            )
        )
    }

    // MARK: - Pickup rules

    func testPickupRequiresDescendingSameSuitRun() {
        let sameSuitRun = [
            TestCards.make(.spades, .nine),
            TestCards.make(.spades, .eight),
            TestCards.make(.spades, .seven)
        ]
        XCTAssertTrue(SharedGameRules.isDescendingSameSuitRun(sameSuitRun))

        let mixedSuitRun = [
            TestCards.make(.spades, .nine),
            TestCards.make(.hearts, .eight)
        ]
        XCTAssertFalse(
            SharedGameRules.isDescendingSameSuitRun(mixedSuitRun),
            "A descending run of mixed suits must not move together"
        )

        let alternatingColorRun = [
            TestCards.make(.spades, .nine),
            TestCards.make(.diamonds, .eight)
        ]
        XCTAssertFalse(SharedGameRules.isDescendingSameSuitRun(alternatingColorRun))

        let gappedSameSuit = [
            TestCards.make(.spades, .nine),
            TestCards.make(.spades, .seven)
        ]
        XCTAssertFalse(SharedGameRules.isDescendingSameSuitRun(gappedSameSuit))

        XCTAssertTrue(SharedGameRules.isDescendingSameSuitRun([TestCards.make(.clubs, .four)]))

        let faceDownLead = [
            TestCards.make(.spades, .nine, isFaceUp: false),
            TestCards.make(.spades, .eight)
        ]
        XCTAssertFalse(SharedGameRules.isDescendingSameSuitRun(faceDownLead))
    }

    func testCandidateSelectionsOfferOnlySameSuitRunSuffixes() {
        // Pile: 9♠ 8♥ 7♥ — the 8♥7♥ suffix and the 7♥ alone are movable;
        // the full mixed-suit stack is not.
        let nineSpades = TestCards.make(.spades, .nine)
        let eightHearts = TestCards.make(.hearts, .eight)
        let sevenHearts = TestCards.make(.hearts, .seven)
        let state = SpiderTestStates.board(
            tableau: [[nineSpades, eightHearts, sevenHearts]]
        )

        let tableauSources = AutoMoveAdvisor.candidateSelections(in: state)
            .compactMap { selection -> Int? in
                guard case .tableau(_, let index) = selection.source else { return nil }
                return index
            }
        XCTAssertEqual(tableauSources.sorted(), [1, 2], "Only the same-suit suffixes are pickable")
    }

    func testFoundationsAreNeverSourcesOrDestinations() {
        // A banked run's King must never be pickable, and a lone Ace must never
        // be droppable on an empty foundation pile.
        let bankedRun = Rank.allCases.map { TestCards.make(.spades, $0) }
        let aceHearts = TestCards.make(.hearts, .ace)
        var foundations: [[Card]] = Array(repeating: [], count: 8)
        foundations[0] = bankedRun
        let state = SpiderTestStates.board(
            tableau: [[aceHearts]],
            foundations: foundations
        )

        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            if case .foundation = selection.source {
                XCTFail("Spider foundations must not be pickup sources")
            }
        }

        let aceSelection = Selection(source: .tableau(pile: 0, index: 0), cards: [aceHearts])
        for destination in AutoMoveAdvisor.legalDestinations(for: aceSelection, in: state) {
            if case .foundation = destination {
                XCTFail("Spider foundations must not be legal destinations")
            }
        }
    }

    func testWholePileMoveToEmptyColumnIsRedundantForAnyLeadRank() {
        // A whole pile led by a mid-rank card parked next to empty columns is a
        // no-op relocation, so the advisor refuses it (players still can).
        let nineSpades = TestCards.make(.spades, .nine)
        let eightSpades = TestCards.make(.spades, .eight)
        let state = SpiderTestStates.board(tableau: [[nineSpades, eightSpades]])

        let wholePile = Selection(
            source: .tableau(pile: 0, index: 0),
            cards: [nineSpades, eightSpades]
        )
        XCTAssertTrue(AutoMoveAdvisor.legalDestinations(for: wholePile, in: state).isEmpty)
    }

    // MARK: - Session move semantics

    func testSessionMovesSameSuitRunAndFlipsExposedCard() {
        let hiddenKing = TestCards.make(.clubs, .king, isFaceUp: false)
        let eightSpades = TestCards.make(.spades, .eight)
        let sevenSpades = TestCards.make(.spades, .seven)
        let nineHearts = TestCards.make(.hearts, .nine)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [[hiddenKing, eightSpades, sevenSpades], [nineHearts]]
        )
        viewModel.configureSpiderNewGame()

        viewModel.selection = Selection(
            source: .tableau(pile: 0, index: 1),
            cards: [eightSpades, sevenSpades]
        )
        XCTAssertTrue(viewModel.tryMoveSelection(to: .tableau(1)))

        XCTAssertEqual(viewModel.state.tableau[1].map(\.id), [nineHearts.id, eightSpades.id, sevenSpades.id])
        XCTAssertEqual(viewModel.state.tableau[0].count, 1)
        XCTAssertTrue(
            viewModel.state.tableau[0][0].isFaceUp,
            "The exposed face-down card should flip when the run leaves"
        )
        XCTAssertEqual(viewModel.movesCount, 1)
    }

    func testSessionRefusesMixedSuitGroupSelection() {
        let nineSpades = TestCards.make(.spades, .nine)
        let eightHearts = TestCards.make(.hearts, .eight)
        let viewModel = SolitaireViewModel()
        viewModel.state = SpiderTestStates.board(
            tableau: [[nineSpades, eightHearts], [TestCards.make(.clubs, .ten)]]
        )
        viewModel.configureSpiderNewGame()

        XCTAssertFalse(viewModel.canSelectTableauCards([nineSpades, eightHearts]))
        XCTAssertFalse(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 0))
        XCTAssertTrue(viewModel.startDragFromTableau(pileIndex: 0, cardIndex: 1))
    }
}

/// Constructs Spider board states for tests: piles are padded to Spider's ten
/// columns, foundations to its eight banked-run piles.
@MainActor
enum SpiderTestStates {
    static func board(
        tableau: [[Card]],
        stock: [Card] = [],
        foundations: [[Card]] = Array(repeating: [], count: 8)
    ) -> GameState {
        var paddedTableau = tableau
        while paddedTableau.count < 10 {
            paddedTableau.append([])
        }
        return GameState(
            variant: .spider,
            stock: stock,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: foundations,
            tableau: paddedTableau
        )
    }

    /// A ten-pile board with a single face-up card in every pile, so stock
    /// deals are legal and the layout is otherwise inert.
    static func fullBoard(topRank: Rank = .five, stock: [Card] = []) -> GameState {
        board(
            tableau: (0..<10).map { _ in [TestCards.make(.spades, topRank)] },
            stock: stock
        )
    }
}
