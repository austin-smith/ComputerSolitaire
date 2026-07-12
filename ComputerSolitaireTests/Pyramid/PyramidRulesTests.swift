import XCTest
@testable import Computer_Solitaire

@MainActor
final class PyramidRulesTests: XCTestCase {
    func testPairAndKingClassification() {
        XCTAssertTrue(PyramidGameRules.isPair(TestCards.make(.spades, .six), TestCards.make(.hearts, .seven)))
        XCTAssertTrue(PyramidGameRules.isPair(TestCards.make(.clubs, .ace), TestCards.make(.clubs, .queen)))
        XCTAssertFalse(PyramidGameRules.isPair(TestCards.make(.spades, .six), TestCards.make(.hearts, .six)))
        XCTAssertFalse(PyramidGameRules.isPair(TestCards.make(.spades, .king), TestCards.make(.hearts, .ace)))
        XCTAssertTrue(PyramidGameRules.isKing(TestCards.make(.spades, .king)))
        XCTAssertFalse(PyramidGameRules.isKing(TestCards.make(.spades, .queen)))
    }

    func testExposedPairIsRemovableAndCoveredPairIsNot() {
        // Bottom row holds a 6 and a 7 (exposed); slot 15 holds a covered 8.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .eight)
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .seven)
        slots[23] = TestCards.make(.diamonds, .five)
        let state = GameStateFixtures.pyramidState(slots: slots)

        XCTAssertTrue(PyramidGameRules.canRemovePair(21, 22, in: state.pyramid))
        XCTAssertTrue(PyramidGameRules.canRemovePair(22, 21, in: state.pyramid))
        // The covered 8 cannot pair with the exposed 5: two cards cover it.
        XCTAssertFalse(PyramidGameRules.canRemovePair(15, 23, in: state.pyramid))
        // A slot never pairs with itself and empty slots never pair.
        XCTAssertFalse(PyramidGameRules.canRemovePair(21, 21, in: state.pyramid))
        XCTAssertFalse(PyramidGameRules.canRemovePair(0, 21, in: state.pyramid))
    }

    func testCoverPairIsRemovableTogether() {
        // Slot 15's only remaining cover is slot 21, and the two sum to 13 — the
        // cover-pair rule removes both in one move.
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .six)
        slots[21] = TestCards.make(.spades, .seven)
        let state = GameStateFixtures.pyramidState(slots: slots)

        XCTAssertTrue(PyramidGameRules.isCoverPair(parent: 15, child: 21, in: state.pyramid))
        XCTAssertTrue(PyramidGameRules.canRemovePair(15, 21, in: state.pyramid))
        XCTAssertTrue(PyramidGameRules.isSelectable(index: 15, in: state.pyramid))

        // With the second cover still present, the parent stays locked.
        var covered = slots
        covered[22] = TestCards.make(.diamonds, .two)
        let coveredState = GameStateFixtures.pyramidState(slots: covered)
        XCTAssertFalse(PyramidGameRules.isCoverPair(parent: 15, child: 21, in: coveredState.pyramid))
        XCTAssertFalse(PyramidGameRules.canRemovePair(15, 21, in: coveredState.pyramid))
        XCTAssertFalse(PyramidGameRules.isSelectable(index: 15, in: coveredState.pyramid))
    }

    func testWasteTopPairing() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .eight)
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .nine)
        let state = GameStateFixtures.pyramidState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .four), TestCards.make(.diamonds, .seven)]
        )

        // Waste top is the 7: it pairs with the exposed 6, not the buried 4 or the
        // covered 8.
        XCTAssertTrue(PyramidGameRules.canRemovePairWithWasteTop(pyramidIndex: 21, in: state))
        XCTAssertFalse(PyramidGameRules.canRemovePairWithWasteTop(pyramidIndex: 15, in: state))
        XCTAssertFalse(PyramidGameRules.canRemovePairWithWasteTop(pyramidIndex: 22, in: state))
    }

    func testKingRemoval() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .king)
        slots[21] = TestCards.make(.spades, .king)
        slots[22] = TestCards.make(.hearts, .two)
        let wasteKing = TestCards.make(.diamonds, .king)
        let state = GameStateFixtures.pyramidState(slots: slots, waste: [wasteKing])

        let exposedKing = Selection(source: .pyramid(index: 21), cards: [state.pyramid[21]!])
        XCTAssertTrue(PyramidGameRules.canRemoveKing(selection: exposedKing, in: state))

        let coveredKing = Selection(source: .pyramid(index: 15), cards: [state.pyramid[15]!])
        XCTAssertFalse(PyramidGameRules.canRemoveKing(selection: coveredKing, in: state))

        let wasteSelection = Selection(source: .waste, cards: [wasteKing])
        XCTAssertTrue(PyramidGameRules.canRemoveKing(selection: wasteSelection, in: state))

        let notAKing = Selection(source: .pyramid(index: 22), cards: [state.pyramid[22]!])
        XCTAssertFalse(PyramidGameRules.canRemoveKing(selection: notAKing, in: state))
    }

    func testRecycleRequiresEmptyStockAndRemainingPasses() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[21] = TestCards.make(.spades, .six)
        let waste = [TestCards.make(.hearts, .nine)]

        XCTAssertTrue(
            PyramidGameRules.canRecycleWaste(
                in: GameStateFixtures.pyramidState(slots: slots, waste: waste, passesUsed: 0)
            )
        )
        XCTAssertTrue(
            PyramidGameRules.canRecycleWaste(
                in: GameStateFixtures.pyramidState(slots: slots, waste: waste, passesUsed: 1)
            )
        )
        XCTAssertFalse(
            PyramidGameRules.canRecycleWaste(
                in: GameStateFixtures.pyramidState(slots: slots, waste: waste, passesUsed: 2)
            )
        )
        XCTAssertFalse(
            PyramidGameRules.canRecycleWaste(
                in: GameStateFixtures.pyramidState(
                    slots: slots,
                    stock: [TestCards.make(.clubs, .three)],
                    waste: waste
                )
            )
        )
        XCTAssertFalse(
            PyramidGameRules.canRecycleWaste(
                in: GameStateFixtures.pyramidState(slots: slots)
            )
        )
    }

    func testStateByApplyingRemovesAPyramidPairToTheDiscard() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.spades, .six)
        let seven = TestCards.make(.hearts, .seven)
        slots[21] = six
        slots[22] = seven
        let state = GameStateFixtures.pyramidState(slots: slots)

        let selection = Selection(source: .pyramid(index: 21), cards: [state.pyramid[21]!])
        guard let next = PyramidGameRules.stateByApplying(
            selection: selection,
            destination: .pyramid(22),
            to: state
        ) else {
            return XCTFail("Expected a legal pair removal")
        }

        XCTAssertNil(next.pyramid[21])
        XCTAssertNil(next.pyramid[22])
        XCTAssertEqual(next.discard.map(\.id), [six.id, seven.id])
        XCTAssertEqual(next.waste, state.waste)
    }

    func testStateByApplyingRemovesAWastePairAndReclampsTheVisibleWaste() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.spades, .six)
        slots[21] = six
        let buried = TestCards.make(.diamonds, .four)
        let seven = TestCards.make(.diamonds, .seven)
        let state = GameStateFixtures.pyramidState(slots: slots, waste: [buried, seven])

        let selection = Selection(source: .waste, cards: [seven])
        guard let next = PyramidGameRules.stateByApplying(
            selection: selection,
            destination: .pyramid(21),
            to: state
        ) else {
            return XCTFail("Expected a legal waste pair removal")
        }

        XCTAssertNil(next.pyramid[21])
        XCTAssertEqual(next.waste.map(\.id), [buried.id])
        XCTAssertEqual(next.wasteDrawCount, 1, "The uncovered waste card becomes playable")
        XCTAssertEqual(next.discard.map(\.id), [seven.id, six.id])
    }

    func testStateByApplyingRemovesACoverPairInOneMove() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        let six = TestCards.make(.clubs, .six)
        let seven = TestCards.make(.spades, .seven)
        slots[15] = six
        slots[21] = seven
        let state = GameStateFixtures.pyramidState(slots: slots)

        let selection = Selection(source: .pyramid(index: 15), cards: [state.pyramid[15]!])
        guard let next = PyramidGameRules.stateByApplying(
            selection: selection,
            destination: .pyramid(21),
            to: state
        ) else {
            return XCTFail("Expected the cover-pair to be one legal move")
        }
        XCTAssertNil(next.pyramid[15])
        XCTAssertNil(next.pyramid[21])
        XCTAssertEqual(next.discard.count, 2)
    }

    func testStateByApplyingRejectsIllegalMoves() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .eight)
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .five)
        let state = GameStateFixtures.pyramidState(slots: slots)

        // 6 + 5 is not 13.
        let six = Selection(source: .pyramid(index: 21), cards: [state.pyramid[21]!])
        XCTAssertNil(PyramidGameRules.stateByApplying(selection: six, destination: .pyramid(22), to: state))
        // The covered 8 cannot pair even though 8 + 5 is 13.
        let eight = Selection(source: .pyramid(index: 15), cards: [state.pyramid[15]!])
        XCTAssertNil(PyramidGameRules.stateByApplying(selection: eight, destination: .pyramid(22), to: state))
        // A non-King cannot go to the discard alone.
        XCTAssertNil(PyramidGameRules.stateByApplying(selection: six, destination: .discard, to: state))
        // Pyramid moves never apply to other variants' states.
        let klondike = GameStateFixtures.seededKlondikeDeal(seed: 1)
        XCTAssertNil(
            PyramidGameRules.stateByApplying(selection: six, destination: .pyramid(22), to: klondike)
        )
    }

    func testAdvisorGeneratesExactlyTheLegalPyramidMoves() {
        var slots = [Card?](repeating: nil, count: PyramidGeometry.cardCount)
        slots[15] = TestCards.make(.clubs, .eight)     // covered by 21/22
        slots[21] = TestCards.make(.spades, .six)
        slots[22] = TestCards.make(.hearts, .seven)
        slots[23] = TestCards.make(.diamonds, .king)
        let state = GameStateFixtures.pyramidState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )

        let selections = AutoMoveAdvisor.candidateSelections(in: state)
        // Waste top + the three exposed bottom-row cards; the covered 8 is not
        // selectable (its covers do not form its pair).
        XCTAssertEqual(selections.count, 4)
        XCTAssertFalse(selections.contains { $0.source == .pyramid(index: 15) })

        let sixSelection = Selection(source: .pyramid(index: 21), cards: [state.pyramid[21]!])
        XCTAssertEqual(
            AutoMoveAdvisor.legalDestinations(for: sixSelection, in: state),
            [.pyramid(22), .waste]
        )

        let kingSelection = Selection(source: .pyramid(index: 23), cards: [state.pyramid[23]!])
        XCTAssertEqual(
            AutoMoveAdvisor.legalDestinations(for: kingSelection, in: state),
            [.discard]
        )

        let wasteSelection = Selection(source: .waste, cards: [state.waste.last!])
        XCTAssertEqual(
            AutoMoveAdvisor.legalDestinations(for: wasteSelection, in: state),
            [.pyramid(21)]
        )

        // Foundations never appear as destinations in Pyramid.
        for selection in selections {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                if case .foundation = destination {
                    XCTFail("Pyramid moves must never target a foundation")
                }
            }
        }
    }

    func testSimulatedStateMatchesStateByApplying() {
        let state = GameStateFixtures.seededPyramidDeal(seed: 3)
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                let simulated = AutoMoveAdvisor.simulatedState(
                    afterMoving: selection,
                    to: destination,
                    in: state,
                    stockDrawCount: 1
                )
                let applied = PyramidGameRules.stateByApplying(
                    selection: selection,
                    destination: destination,
                    to: state
                )
                XCTAssertEqual(simulated, applied, "Advisor and rules must agree on move effects")
            }
        }
    }
}
