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

    func testWasteViewPrunesOnEqualInputsButSeesTopCardTiltRerolls() {
        let session = SolitaireViewModel(variant: .klondike)
        let cards = [TestCards.make(.clubs, .four), TestCards.make(.diamonds, .nine)]
        let topID = cards[1].id
        let hintToken = UUID()
        // Fresh closures/bindings per call; only `tilts` varies.
        func makeWasteView(tilts: [UUID: Double]) -> WasteView {
            WasteView(
                session: session,
                cards: cards,
                selection: session.selectionSnapshot,
                cardSize: CGSize(width: 50, height: 70),
                fanSpacing: 14,
                isHintTargeted: false,
                isCardTiltEnabled: true,
                cardTilts: .constant(tilts),
                hiddenCardIDs: [],
                hintedCardIDs: [],
                hintWiggleToken: hintToken,
                drawingCardIDs: [],
                fanProgress: [:],
                dragGesture: anyDragGesture()
            )
        }

        let base = makeWasteView(tilts: [topID: 1.2])
        XCTAssertEqual(base, makeWasteView(tilts: [topID: 1.2]))

        // The waste-return tilt reroll mutates only the tilt dictionary; the
        // captured topCardTilt must surface it or the pile would prune past
        // the write and visibly re-tilt on reveal.
        XCTAssertNotEqual(base, makeWasteView(tilts: [topID: -1.7]))

        // A tilt write for a non-top card cannot affect rendering here and
        // must not defeat pruning.
        XCTAssertEqual(base, makeWasteView(tilts: [topID: 1.2, cards[0].id: 0.4]))
    }

    private func makeFoundationView(
        session: SolitaireViewModel,
        pile: [Card]?,
        placeholder: FoundationPlaceholder,
        hintWiggleToken: UUID
    ) -> FoundationView {
        FoundationView(
            session: session,
            pile: pile,
            index: 0,
            placeholder: placeholder,
            selection: session.selectionSnapshot,
            cardSize: CGSize(width: 50, height: 70),
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

    func testFoundationViewEquatableCoversPileAndPlaceholder() {
        let session = SolitaireViewModel(variant: .klondike)
        let pile = [TestCards.make(.spades, .ace)]
        let token = UUID()
        let base = makeFoundationView(session: session, pile: pile, placeholder: .ace, hintWiggleToken: token)
        XCTAssertEqual(
            base,
            makeFoundationView(session: session, pile: pile, placeholder: .ace, hintWiggleToken: token)
        )
        XCTAssertNotEqual(
            base,
            makeFoundationView(session: session, pile: pile + [TestCards.make(.spades, .two)], placeholder: .ace, hintWiggleToken: token)
        )
        XCTAssertNotEqual(
            base,
            makeFoundationView(session: session, pile: nil, placeholder: .ace, hintWiggleToken: token)
        )
        XCTAssertNotEqual(
            base,
            makeFoundationView(session: session, pile: pile, placeholder: .baseRank(.five), hintWiggleToken: token)
        )
    }
}
