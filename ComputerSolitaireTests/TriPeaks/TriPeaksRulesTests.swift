import XCTest
@testable import Computer_Solitaire

@MainActor
final class TriPeaksRulesTests: XCTestCase {
    func testRankAdjacencyWrapsAtAceAndKing() {
        XCTAssertTrue(TriPeaksGameRules.ranksAdjacentWithWrap(.ace, .two))
        XCTAssertTrue(TriPeaksGameRules.ranksAdjacentWithWrap(.ace, .king))
        XCTAssertTrue(TriPeaksGameRules.ranksAdjacentWithWrap(.king, .queen))
        XCTAssertTrue(TriPeaksGameRules.ranksAdjacentWithWrap(.seven, .eight))
        XCTAssertTrue(TriPeaksGameRules.ranksAdjacentWithWrap(.seven, .six))

        XCTAssertFalse(TriPeaksGameRules.ranksAdjacentWithWrap(.ace, .three))
        XCTAssertFalse(TriPeaksGameRules.ranksAdjacentWithWrap(.king, .two))
        XCTAssertFalse(TriPeaksGameRules.ranksAdjacentWithWrap(.seven, .seven))
        XCTAssertFalse(TriPeaksGameRules.ranksAdjacentWithWrap(.queen, .ace))
    }

    func testCanPlayRequiresUncoveredAndAdjacency() {
        // Base 18/19 present and covering row-2 slot 9; waste top is a 7.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[9] = TestCards.make(.clubs, .eight)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .ten)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )

        XCTAssertTrue(
            TriPeaksGameRules.canPlay(index: 18, in: state),
            "An uncovered adjacent card plays (suit ignored)"
        )
        XCTAssertFalse(
            TriPeaksGameRules.canPlay(index: 19, in: state),
            "Ten is not adjacent to seven"
        )
        XCTAssertFalse(
            TriPeaksGameRules.canPlay(index: 9, in: state),
            "A covered card never plays, adjacent rank or not"
        )
        XCTAssertFalse(
            TriPeaksGameRules.canPlay(index: 27, in: state),
            "An empty slot never plays"
        )
    }

    func testStateByApplyingMovesCardToWasteAndIncrementsChain() throws {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        let played = TestCards.make(.spades, .six)
        slots[18] = played
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)],
            chainLength: 2
        )

        let next = try XCTUnwrap(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 18), cards: [played]),
                destination: .waste,
                to: state
            )
        )
        XCTAssertNil(next.triPeaks[18])
        XCTAssertEqual(next.waste.last?.id, played.id)
        XCTAssertEqual(next.waste.count, state.waste.count + 1)
        XCTAssertEqual(next.triPeaksChainLength, 3)
        XCTAssertEqual(next.wasteDrawCount, 1)
    }

    func testStateByApplyingFlipsNewlyUncoveredCards() throws {
        // Slot 9 is covered by base 18 and 19; removing the second coverer
        // flips it, removing only the first does not.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[9] = TestCards.make(.clubs, .four)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .seven)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .eight)]
        )
        XCTAssertEqual(state.triPeaks[9]?.isFaceUp, false)

        let afterFirst = try XCTUnwrap(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 19), cards: [state.triPeaks[19]!]),
                destination: .waste,
                to: state
            )
        )
        XCTAssertEqual(afterFirst.triPeaks[9]?.isFaceUp, false, "One coverer remains")

        let afterSecond = try XCTUnwrap(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 18), cards: [afterFirst.triPeaks[18]!]),
                destination: .waste,
                to: afterFirst
            )
        )
        XCTAssertEqual(afterSecond.triPeaks[9]?.isFaceUp, true, "Both coverers gone: flips")
    }

    func testStateByApplyingRejectsIllegalMoves() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[9] = TestCards.make(.clubs, .eight)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .ten)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )

        // Covered card.
        XCTAssertNil(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 9), cards: [state.triPeaks[9]!]),
                destination: .waste,
                to: state
            )
        )
        // Non-adjacent rank.
        XCTAssertNil(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 19), cards: [state.triPeaks[19]!]),
                destination: .waste,
                to: state
            )
        )
        // Stale selection: right slot, wrong card identity.
        XCTAssertNil(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(
                    source: .triPeaks(index: 18),
                    cards: [TestCards.make(.spades, .six)]
                ),
                destination: .waste,
                to: state
            )
        )
        // Wrong destination.
        XCTAssertNil(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 18), cards: [state.triPeaks[18]!]),
                destination: .discard,
                to: state
            )
        )
        // Wrong variant.
        var pyramidState = state
        pyramidState.variant = .pyramid
        XCTAssertNil(
            TriPeaksGameRules.stateByApplying(
                selection: Selection(source: .triPeaks(index: 18), cards: [state.triPeaks[18]!]),
                destination: .waste,
                to: pyramidState
            )
        )
    }

    func testClearedPeakCountReadsApexSlots() {
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        XCTAssertEqual(TriPeaksGameRules.clearedPeakCount(in: GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        ).triPeaks), 3)

        slots[0] = TestCards.make(.clubs, .two)
        slots[2] = TestCards.make(.spades, .nine)
        let partial = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )
        XCTAssertEqual(TriPeaksGameRules.clearedPeakCount(in: partial.triPeaks), 1)
    }

    func testAdvisorGeneratesExactlyTheLegalTriPeaksMoves() {
        // Uncovered: 0 (apex, subtree clear) and the two base cards. Playable
        // onto the 7: the 6 and the 8 only.
        var slots = [Card?](repeating: nil, count: TriPeaksGeometry.cardCount)
        slots[0] = TestCards.make(.clubs, .jack)
        slots[18] = TestCards.make(.spades, .six)
        slots[19] = TestCards.make(.hearts, .eight)
        let state = GameStateFixtures.triPeaksState(
            slots: slots,
            waste: [TestCards.make(.diamonds, .seven)]
        )

        let sources = AutoMoveAdvisor.candidateSelections(in: state).map(\.source)
        XCTAssertEqual(
            sources,
            [.triPeaks(index: 0), .triPeaks(index: 18), .triPeaks(index: 19)],
            "Every uncovered card is a candidate; covered and empty slots are not"
        )

        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            let destinations = AutoMoveAdvisor.legalDestinations(for: selection, in: state)
            switch selection.source {
            case .triPeaks(let index) where index == 0:
                XCTAssertTrue(destinations.isEmpty, "Jack is not adjacent to seven")
            default:
                XCTAssertEqual(destinations, [.waste])
            }
        }
    }

    func testSimulatedStateMatchesStateByApplying() throws {
        let state = GameStateFixtures.seededTriPeaksDeal(seed: 3)
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                let simulated = AutoMoveAdvisor.simulatedState(
                    afterMoving: selection,
                    to: destination,
                    in: state,
                    stockDrawCount: 1
                )
                let applied = TriPeaksGameRules.stateByApplying(
                    selection: selection,
                    destination: destination,
                    to: state
                )
                XCTAssertEqual(simulated, applied)
                XCTAssertNotNil(applied, "Advisor-legal moves must apply")
            }
        }
    }
}
