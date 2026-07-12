import XCTest
@testable import Computer_Solitaire

@MainActor
final class TapMovePolicyTests: XCTestCase {
    // MARK: - Taps never dead-end

    func testTapAlwaysResolvesWhenLegalDestinationExistsAcrossRandomFreeCellPlay() {
        var generator = SeededRandomNumberGenerator(seed: 99)
        for seed in 1...10 {
            var state = GameStateFixtures.seededFreeCellDeal(seed: UInt64(seed))
            for _ in 0..<40 {
                for pile in state.tableau.indices {
                    guard let top = state.tableau[pile].last else { continue }
                    let selection = Selection(
                        source: .tableau(pile: pile, index: state.tableau[pile].count - 1),
                        cards: [top]
                    )
                    let legal = AutoMoveAdvisor.legalDestinations(for: selection, in: state)
                    guard !legal.isEmpty else { continue }
                    XCTAssertNotNil(
                        TapMovePolicy.bestDestination(for: selection, in: state),
                        "Tap must resolve while a legal destination exists"
                    )
                }
                guard let next = randomAdvance(state, using: &generator) else { break }
                state = next
            }
        }
    }

    // MARK: - FreeCell destination preferences

    func testFreeCellSafeFoundationMoveBeatsTableauBuild() {
        // 2♠ can go to foundation (safe: rank <= 2) or onto the red 3.
        let twoSpades = TestCards.make(.spades, .two)
        let threeHearts = TestCards.make(.hearts, .three)
        let state = freeCellState(
            freeCells: [nil, nil, nil, nil],
            foundations: [[TestCards.make(.spades, .ace)], [], [], []],
            tableau: [[twoSpades], [threeHearts], [], [], [], [], [], []]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: [twoSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .foundation(0))
    }

    func testFreeCellUnsafeFoundationMoveLosesToTableauBuild() {
        // 5♠ is foundation-eligible but unsafe (red foundations far behind); prefer the red 6.
        let fiveSpades = TestCards.make(.spades, .five)
        let sixHearts = TestCards.make(.hearts, .six)
        let state = freeCellState(
            freeCells: [nil, nil, nil, nil],
            foundations: [
                [TestCards.make(.spades, .ace), TestCards.make(.spades, .two),
                 TestCards.make(.spades, .three), TestCards.make(.spades, .four)],
                [], [], []
            ],
            tableau: [[fiveSpades], [sixHearts], [], [], [], [], [], []]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: [fiveSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .tableau(1))
    }

    // MARK: - Yukon destination preferences

    func testYukonSafeFoundationMoveBeatsTableauBuild() {
        // 2♠ can go to foundation (safe: rank <= 2) or onto the red 3.
        let twoSpades = TestCards.make(.spades, .two)
        let threeHearts = TestCards.make(.hearts, .three)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [[TestCards.make(.spades, .ace)], [], [], []],
            tableau: [[twoSpades], [threeHearts], [], [], [], [], []]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: [twoSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .foundation(0))
    }

    func testYukonUnsafeFoundationMoveLosesToTableauBuild() {
        // 5♠ is foundation-eligible but unsafe (red foundations far behind); with no
        // stock to refill the board, the tap should prefer keeping it on the red 6.
        let fiveSpades = TestCards.make(.spades, .five)
        let sixHearts = TestCards.make(.hearts, .six)
        let state = GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: [
                [TestCards.make(.spades, .ace), TestCards.make(.spades, .two),
                 TestCards.make(.spades, .three), TestCards.make(.spades, .four)],
                [], [], []
            ],
            tableau: [[fiveSpades], [sixHearts], [], [], [], [], []]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 0), cards: [fiveSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .tableau(1))
    }

    func testFreeCellFreeCellIsLastResort() {
        // King with no tableau fit: only free cells remain, and the tap should use one.
        let kingSpades = TestCards.make(.spades, .king)
        let sevenHearts = TestCards.make(.hearts, .seven)
        let state = freeCellState(
            freeCells: [nil, nil, nil, nil],
            foundations: [[], [], [], []],
            tableau: [
                [sevenHearts, kingSpades],
                [TestCards.make(.clubs, .four)],
                [TestCards.make(.diamonds, .nine)],
                [TestCards.make(.spades, .six)],
                [TestCards.make(.hearts, .queen)],
                [TestCards.make(.clubs, .ten)],
                [TestCards.make(.diamonds, .two)],
                [TestCards.make(.clubs, .ace)]
            ]
        )
        let selection = Selection(source: .tableau(pile: 0, index: 1), cards: [kingSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .freeCell(0))
    }

    func testFoundationSourceTapsNeverAutoMove() {
        // The 2♠ on the foundation could legally return to the red 3, but taps must not do that.
        let twoSpades = TestCards.make(.spades, .two)
        let threeHearts = TestCards.make(.hearts, .three)
        let state = freeCellState(
            freeCells: [nil, nil, nil, nil],
            foundations: [[TestCards.make(.spades, .ace), twoSpades], [], [], []],
            tableau: [[threeHearts], [], [], [], [], [], [], []]
        )
        let selection = Selection(source: .foundation(pile: 0), cards: [twoSpades])

        XCTAssertNil(TapMovePolicy.bestDestination(for: selection, in: state))
    }

    // MARK: - Klondike destination preferences

    func testKlondikeFoundationBeatsTableauBuild() {
        let aceSpades = TestCards.make(.spades, .ace)
        let twoHearts = TestCards.make(.hearts, .two)
        let state = GameState(
            stock: [],
            waste: [aceSpades],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: [[twoHearts], [], [], [], [], [], []]
        )
        let selection = Selection(source: .waste, cards: [aceSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .foundation(0))
    }

    func testKlondikePrefersLongerBuildBetweenTableauOptions() {
        // 5♠ fits on either red 6; prefer the 6 sitting on a longer ordered run.
        let fiveSpades = TestCards.make(.spades, .five)
        let sixHearts = TestCards.make(.hearts, .six)
        let sixDiamonds = TestCards.make(.diamonds, .six)
        let sevenClubs = TestCards.make(.clubs, .seven)
        let state = GameState(
            stock: [],
            waste: [fiveSpades],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: [[sixHearts], [sevenClubs, sixDiamonds], [], [], [], [], []]
        )
        let selection = Selection(source: .waste, cards: [fiveSpades])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .tableau(1))
    }

    // MARK: - Safe foundation rule

    func testSafeFoundationRule() {
        var state = freeCellState(
            freeCells: [nil, nil, nil, nil],
            foundations: [
                [TestCards.make(.spades, .ace), TestCards.make(.spades, .two), TestCards.make(.spades, .three)],
                [TestCards.make(.clubs, .ace), TestCards.make(.clubs, .two)],
                [TestCards.make(.hearts, .ace), TestCards.make(.hearts, .two), TestCards.make(.hearts, .three)],
                [TestCards.make(.diamonds, .ace), TestCards.make(.diamonds, .two), TestCards.make(.diamonds, .three)]
            ],
            tableau: Array(repeating: [], count: 8)
        )

        // 4♠: both red foundations at 3 (>= 3) and other black at 2 (>= 2) → safe.
        XCTAssertTrue(TapMovePolicy.isSafeFoundationMove(card: TestCards.make(.spades, .four), in: state))
        // 4♥: opposite (black) minimum is 2 < 3 → unsafe.
        XCTAssertFalse(TapMovePolicy.isSafeFoundationMove(card: TestCards.make(.hearts, .four), in: state))
        // Aces and twos are always safe.
        XCTAssertTrue(TapMovePolicy.isSafeFoundationMove(card: TestCards.make(.clubs, .two), in: state))

        state.foundations[1] = []
        XCTAssertTrue(TapMovePolicy.isSafeFoundationMove(card: TestCards.make(.hearts, .ace), in: state))
    }

    // MARK: - Pyramid destination preferences

    func testPyramidPairOnTheBoardBeatsAWastePair() {
        // The 6 can pair with the exposed 7 on the board or the 7 on the waste;
        // the board pair removes two pyramid cards, so it wins.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.spades, .six)
        slots[21] = six
        slots[22] = TestCards.make(.hearts, .seven)
        let state = GameStateFixtures.pyramidState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )
        let selection = Selection(source: .pyramid(index: 21), cards: [six])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .pyramid(22))
    }

    func testPyramidEqualPartnersPreferTheLowestSlot() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.spades, .six)
        slots[21] = six
        slots[22] = TestCards.make(.hearts, .seven)
        slots[23] = TestCards.make(.clubs, .seven)
        let state = GameStateFixtures.pyramidState(slots: slots)
        let selection = Selection(source: .pyramid(index: 21), cards: [six])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .pyramid(22))
    }

    func testPyramidKingResolvesToTheDiscard() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let king = TestCards.make(.diamonds, .king)
        slots[21] = king
        slots[22] = TestCards.make(.hearts, .seven)
        let state = GameStateFixtures.pyramidState(slots: slots)
        let selection = Selection(source: .pyramid(index: 21), cards: [king])

        XCTAssertEqual(TapMovePolicy.bestDestination(for: selection, in: state), .discard)
    }

    // MARK: - Helpers

    private func freeCellState(
        freeCells: [Card?],
        foundations: [[Card]],
        tableau: [[Card]]
    ) -> GameState {
        GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: freeCells,
            foundations: foundations,
            tableau: tableau
        )
    }

    private func randomAdvance(
        _ state: GameState,
        using generator: inout SeededRandomNumberGenerator
    ) -> GameState? {
        var moves: [(Selection, Destination)] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            if case .foundation = selection.source { continue }
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                moves.append((selection, destination))
            }
        }
        guard let (selection, destination) = moves.randomElement(using: &generator) else { return nil }
        return AutoMoveAdvisor.simulatedState(
            afterMoving: selection,
            to: destination,
            in: state,
            stockDrawCount: DrawMode.three.rawValue
        )
    }
}
