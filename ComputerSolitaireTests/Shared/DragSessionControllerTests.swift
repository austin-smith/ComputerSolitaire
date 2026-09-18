import Observation
import Synchronization
import XCTest
@testable import Computer_Solitaire

@MainActor
final class DragSessionControllerTests: XCTestCase {
    func testEveryVariantUsesTheExistingMoveRulesAndPreservesCards() {
        withSession { model in
            for variant in GameVariant.allCases {
                model.state = GameState.newGame(variant: variant)
                let candidates = AutoMoveAdvisor.candidateSelections(in: model.state)
                var pickupCount = 0
                for candidate in candidates {
                    let initial = model.state
                    let controller = DragSessionController()
                    let items = begin(controller, cardIDs: [candidate.cards[0].id], in: model)
                    guard !items.isEmpty else { continue }
                    pickupCount += 1
                    XCTAssertEqual(items.map(\.id), model.selection?.cards.map(\.id))
                    if let target = AutoMoveAdvisor.legalDestinations(for: candidate, in: initial).first {
                        XCTAssertTrue(controller.complete(items: items, to: target, in: model), "\(variant)")
                        XCTAssertFalse(controller.isActive)
                        XCTAssertFalse(model.isDragging)
                        XCTAssertFalse(controller.complete(items: items, to: target, in: model))
                    } else {
                        controller.cancel(in: model)
                        XCTAssertEqual(model.state, initial)
                    }
                    XCTAssertEqual(model.state.allCards.count, initial.allCards.count)
                    XCTAssertEqual(Set(model.state.allCards.map(\.id)), Set(initial.allCards.map(\.id)))
                    XCTAssertTrue(model.state.hasNoDuplicateCardIDs)
                    controller.end(in: model)
                    model.state = initial
                }
                XCTAssertGreaterThan(pickupCount, 0, "No pickup coverage for \(variant)")
            }
        }
    }

    func testPayloadRefreshesAreStableAndCannotReviveCancelledSession() {
        withSession { model in
            let cardID = model.state.tableau[0][0].id
            let controller = DragSessionController()
            let items = begin(controller, cardIDs: [cardID], in: model)
            XCTAssertFalse(items.isEmpty)
            XCTAssertEqual(begin(controller, cardIDs: [cardID], in: model), items)
            controller.cancel(in: model)
            XCTAssertFalse(controller.isActive)
            XCTAssertTrue(begin(controller, cardIDs: [cardID], in: model).isEmpty)
            controller.end(in: model)
            let fresh = begin(controller, cardIDs: [cardID], in: model)
            XCTAssertFalse(fresh.isEmpty)
            XCTAssertNotEqual(fresh, items)
            controller.end(in: model)
        }
    }

    func testDropCommitsWhenGestureEndsBeforeDataArrives() {
        withSession { model in
            let ace = TestCards.make(.spades, .ace)
            model.state.tableau = [[ace]] + Array(repeating: [], count: 6)
            let controller = DragSessionController()
            let items = begin(controller, cardIDs: [ace.id], in: model)
            controller.finishInteraction(in: model)
            XCTAssertFalse(model.isDragging)
            XCTAssertFalse(controller.isActive)
            XCTAssertTrue(controller.canDrop(to: .foundation(0), in: model))
            XCTAssertTrue(controller.complete(items: items, to: .foundation(0), in: model))
            XCTAssertEqual(model.state.foundations[0].map(\.id), [ace.id])
            XCTAssertNil(controller.dragID)
        }
    }

    func testNewDragSupersedesAnEndedDragsDelayedTransfer() {
        withSession { model in
            let ace = TestCards.make(.spades, .ace)
            model.state.tableau = [[ace]] + Array(repeating: [], count: 6)
            let controller = DragSessionController()
            let oldItems = begin(controller, cardIDs: [ace.id], in: model)
            controller.finishInteraction(in: model)
            let items = begin(controller, cardIDs: [ace.id], in: model)
            XCTAssertFalse(controller.complete(items: oldItems, to: .foundation(0), in: model))
            XCTAssertTrue(controller.isActive)
            XCTAssertTrue(controller.complete(items: items, to: .foundation(0), in: model))
            controller.finishInteraction(in: model)
            XCTAssertNil(controller.dragID)
        }
    }

    func testWholeStackUsesBoardOrderRegardlessOfTransferOrder() {
        withSession { model in
            let nine = TestCards.make(.spades, .nine)
            let eight = TestCards.make(.hearts, .eight)
            let ten = TestCards.make(.diamonds, .ten)
            model.state.tableau = [[nine, eight], [ten]] + Array(repeating: [], count: 5)
            let controller = DragSessionController()
            let items = begin(controller, cardIDs: [nine.id], in: model)
            XCTAssertEqual(items.map(\.id), [nine.id, eight.id])
            XCTAssertFalse(controller.complete(items: [items[0]], to: .tableau(1), in: model))
            XCTAssertFalse(controller.complete(items: [items[0], items[0]], to: .tableau(1), in: model))
            XCTAssertTrue(controller.matches(cardIDs: items.reversed().map(\.id), in: model))
            XCTAssertTrue(controller.complete(items: items.reversed(), to: .tableau(1), in: model))
            XCTAssertEqual(model.state.tableau[1].map(\.id), [ten.id, nine.id, eight.id])
            XCTAssertTrue(model.state.tableau[0].isEmpty)
        }
    }

    func testInvalidDropDoesNotMutateState() {
        withSession { model in
            let six = TestCards.make(.hearts, .six)
            model.state.tableau = [[six]] + Array(repeating: [], count: 6)
            let initial = model.state
            let controller = DragSessionController()
            let items = begin(controller, cardIDs: [six.id], in: model)
            XCTAssertFalse(controller.complete(items: items, to: .foundation(0), in: model))
            controller.cancel(in: model)
            XCTAssertEqual(model.state, initial)
            XCTAssertNil(model.selection)
            XCTAssertFalse(model.isDragging)
        }
    }

    func testAnotherBoardAndPreviousDragCannotSupplyThePayload() {
        withSession { model in
            let ace = TestCards.make(.spades, .ace)
            model.state.tableau = [[ace]] + Array(repeating: [], count: 6)
            let controller = DragSessionController()
            let oldItems = begin(controller, cardIDs: [ace.id], in: model)
            let otherBoard = DragSessionController()
            XCTAssertFalse(otherBoard.matches(cardIDs: [ace.id], in: model))
            XCTAssertFalse(otherBoard.complete(items: oldItems, to: .foundation(0), in: model))
            controller.end(in: model)
            let items = begin(controller, cardIDs: [ace.id], in: model)
            XCTAssertNotEqual(items, oldItems)
            XCTAssertFalse(controller.complete(items: oldItems, to: .foundation(0), in: model))
            XCTAssertTrue(controller.complete(items: items, to: .foundation(0), in: model))
        }
    }

    func testBoardChangeInvalidatesDragEvenWhenPositionIsRestored() {
        withSession { model in
            let ace = TestCards.make(.spades, .ace)
            model.state.tableau = [[ace]] + Array(repeating: [], count: 6)
            let initial = model.state
            let controller = DragSessionController()
            let items = begin(controller, cardIDs: [ace.id], in: model)
            model.drawFromStock()
            XCTAssertFalse(controller.matches(cardIDs: [ace.id], in: model))
            controller.invalidateIfBoardChanged(in: model)
            model.state = initial
            XCTAssertFalse(controller.complete(items: items, to: .foundation(0), in: model))
            XCTAssertFalse(controller.isActive)
        }
    }

    func testFaceDownCardsAndUnknownIDsDoNotStartDrag() {
        withSession { model in
            let hidden = TestCards.make(.spades, .ace, isFaceUp: false)
            model.state.tableau = [[hidden]] + Array(repeating: [], count: 6)
            let controller = DragSessionController()
            for ids in [[hidden.id], [UUID()], [], [hidden.id, UUID()]] {
                XCTAssertTrue(begin(controller, cardIDs: ids, in: model).isEmpty)
                XCTAssertFalse(controller.isActive)
                XCTAssertFalse(model.isDragging)
            }
        }
    }

    func testPreparingPayloadDoesNotPickUpOrHideCards() {
        withSession { model in
            let controller = DragSessionController()
            let initial = model.state
            let selection = model.selection
            let invalidations = Mutex(0)
            withObservationTracking {
                _ = controller.isActive
            } onChange: {
                invalidations.withLock { $0 += 1 }
            }
            let cardID = model.state.tableau[0][0].id
            let items = controller.prepare(cardIDs: [cardID], in: model)
            XCTAssertFalse(items.isEmpty)
            XCTAssertEqual(controller.prepare(cardIDs: [cardID], in: model), items)
            XCTAssertEqual(model.state, initial)
            XCTAssertEqual(model.selection, selection)
            XCTAssertFalse(model.isDragging)
            XCTAssertFalse(controller.isActive)
            XCTAssertEqual(invalidations.withLock { $0 }, 0)
            XCTAssertFalse(controller.canDrop(to: .foundation(0), in: model))
            XCTAssertTrue(controller.activate(in: model, startDrag: model.startDrag))
            XCTAssertTrue(model.isDragging)
            XCTAssertTrue(controller.isActive)
            XCTAssertEqual(invalidations.withLock { $0 }, 1)
            controller.end(in: model)
        }
    }

    func testAbandonedPreviewDoesNotBlockAnotherCardDrag() {
        withSession { model in
            let controller = DragSessionController()
            let firstID = model.state.tableau[0][0].id
            let secondID = model.state.tableau[1].last!.id
            let first = controller.prepare(cardIDs: [firstID], in: model)
            let second = controller.prepare(cardIDs: [secondID], in: model)
            XCTAssertFalse(first.isEmpty)
            XCTAssertFalse(second.isEmpty)
            XCTAssertNotEqual(first[0].dragID, second[0].dragID)
            XCTAssertTrue(controller.activate(in: model, startDrag: model.startDrag))
            XCTAssertEqual(model.selection?.cards.first?.id, secondID)
            controller.end(in: model)
        }
    }

    private func begin(_ controller: DragSessionController, cardIDs: [UUID], in model: SolitaireViewModel) -> [CardDragItem] {
        let items = controller.prepare(cardIDs: cardIDs, in: model)
        guard !items.isEmpty, controller.activate(in: model, startDrag: model.startDrag) else { return [] }
        return items
    }

    private func withSession(_ body: (SolitaireViewModel) -> Void) {
        SessionTestHarness.withIsolatedStatsStore {
            body(SolitaireViewModel())
        }
    }
}
