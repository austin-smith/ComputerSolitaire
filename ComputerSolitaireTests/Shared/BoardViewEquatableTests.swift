import SwiftUI
import XCTest
@testable import Computer_Solitaire

/// Regression guard for the board views' manual `==`: SwiftUI silently
/// skips a pruned view's body, so a rendered input that someone adds without
/// extending `==` would show up as a stale board, not a compile error. Each
/// converted view asserts both directions — equal when only the excluded
/// fields differ (fresh gesture closures), unequal when any rendered input
/// is perturbed.
@MainActor
final class BoardViewEquatableTests: XCTestCase {
    private func anyDragGesture() -> (DragOrigin) -> AnyGesture<DragGesture.Value> {
        { _ in AnyGesture(DragGesture()) }
    }

    private func makeTableauPileView(
        session: SolitaireViewModel,
        pile: [Card],
        selection: SelectionSnapshot,
        hintWiggleToken: UUID
    ) -> TableauPileView {
        TableauPileView(
            session: session,
            pile: pile,
            pileIndex: 0,
            variant: .klondike,
            selection: selection,
            cardSize: CGSize(width: 50, height: 70),
            faceDownOffset: 8,
            faceUpOffset: 18,
            maxPileHeight: 400,
            isTargeted: false,
            isHintTargeted: false,
            hintHighlightOpacity: 0,
            isCardTiltEnabled: true,
            cardTilts: .constant([:]),
            hiddenCardIDs: [],
            hintedCardIDs: [],
            hintWiggleToken: hintWiggleToken,
            dragGesture: anyDragGesture()
        )
    }

    func testTableauPileViewPrunesWhenOnlyExcludedFieldsDiffer() {
        let session = SolitaireViewModel(variant: .klondike)
        let pile = [TestCards.make(.spades, .king), TestCards.make(.hearts, .queen)]
        let selection = session.selectionSnapshot
        let token = UUID()
        // Fresh closures and a fresh binding on the right side — the excluded
        // fields — must not defeat pruning.
        let lhs = makeTableauPileView(session: session, pile: pile, selection: selection, hintWiggleToken: token)
        let rhs = makeTableauPileView(session: session, pile: pile, selection: selection, hintWiggleToken: token)
        XCTAssertEqual(lhs, rhs)
    }

    func testTableauPileViewReRendersWhenRenderedInputsChange() {
        let session = SolitaireViewModel(variant: .klondike)
        let pile = [TestCards.make(.spades, .king), TestCards.make(.hearts, .queen)]
        let selection = session.selectionSnapshot
        let token = UUID()
        let base = makeTableauPileView(session: session, pile: pile, selection: selection, hintWiggleToken: token)

        var flippedPile = pile
        flippedPile[1].isFaceUp = false
        XCTAssertNotEqual(
            base,
            makeTableauPileView(session: session, pile: flippedPile, selection: selection, hintWiggleToken: token)
        )

        let selected = SelectionSnapshot(
            selection: Selection(source: .tableau(pile: 0, index: 1), cards: [pile[1]]),
            isDragging: false
        )
        XCTAssertNotEqual(
            base,
            makeTableauPileView(session: session, pile: pile, selection: selected, hintWiggleToken: token)
        )

        XCTAssertNotEqual(
            base,
            makeTableauPileView(session: session, pile: pile, selection: selection, hintWiggleToken: UUID())
        )

        let otherSession = SolitaireViewModel(variant: .klondike)
        XCTAssertNotEqual(
            base,
            makeTableauPileView(session: otherSession, pile: pile, selection: selection, hintWiggleToken: token)
        )
    }
}
