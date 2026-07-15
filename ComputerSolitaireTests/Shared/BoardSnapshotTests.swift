import XCTest
@testable import Computer_Solitaire

/// The snapshots are what board views render from instead of reading the
/// observable session; these tests pin each derived field to the session
/// state it projects.
@MainActor
final class BoardSnapshotTests: XCTestCase {
    func testSelectionSnapshotWithNoSelection() {
        let session = SolitaireViewModel(variant: .klondike)
        let snapshot = session.selectionSnapshot
        XCTAssertFalse(snapshot.isDragging)
        XCTAssertNil(snapshot.source)
        XCTAssertNil(snapshot.dragSource)
        XCTAssertTrue(snapshot.selectedCardIDs.isEmpty)
    }

    func testSelectionSnapshotMatchesSessionSelection() {
        let session = SolitaireViewModel(variant: .klondike)
        guard let pileIndex = session.state.tableau.lastIndex(where: { $0.count > 1 }) else {
            return XCTFail("expected a multi-card tableau pile in a fresh deal")
        }
        let cardIndex = session.state.tableau[pileIndex].count - 1
        session.selectFromTableau(pileIndex: pileIndex, cardIndex: cardIndex)
        guard let selection = session.selection else {
            return XCTFail("expected a selection")
        }

        let tapped = session.selectionSnapshot
        XCTAssertFalse(tapped.isDragging)
        XCTAssertEqual(tapped.source, selection.source)
        XCTAssertNil(tapped.dragSource, "tap selections are not drag sources")
        for card in selection.cards {
            XCTAssertEqual(tapped.isSelected(card), session.isSelected(card: card))
        }

        session.isDragging = true
        let dragged = session.selectionSnapshot
        XCTAssertTrue(dragged.isDragging)
        XCTAssertEqual(dragged.dragSource, selection.source)
    }

    func testSnapshotsOfTheSamePositionAreEqual() {
        let session = SolitaireViewModel(variant: .klondike)
        XCTAssertEqual(session.topRowSnapshot, session.topRowSnapshot)
        XCTAssertEqual(session.selectionSnapshot, session.selectionSnapshot)
    }

    func testTopRowSnapshotChangesWithAStockDraw() {
        let session = SolitaireViewModel(variant: .klondike)
        let before = session.topRowSnapshot
        session.handleStockTap()
        let after = session.topRowSnapshot
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.stockCount, session.state.stock.count)
        XCTAssertEqual(after.visibleWasteCards, session.visibleWasteCards())
    }

    func testTopRowSnapshotVisibleWasteMatchesSessionAcrossVariants() {
        for variant in GameVariant.allCases {
            let session = SolitaireViewModel(variant: variant)
            session.handleStockTap()
            let snapshot = session.topRowSnapshot
            XCTAssertEqual(snapshot.visibleWasteCards, session.visibleWasteCards(), "\(variant)")
            XCTAssertEqual(snapshot.stockCount, session.state.stock.count, "\(variant)")
            XCTAssertEqual(snapshot.canInteractWithStock, session.canInteractWithStock, "\(variant)")
            XCTAssertEqual(snapshot.foundations, session.state.foundations, "\(variant)")
        }
    }

    func testFoundationPlaceholderIsAceOutsideCanfield() {
        let session = SolitaireViewModel(variant: .klondike)
        XCTAssertEqual(session.topRowSnapshot.foundationPlaceholder, .ace)
    }

    func testFoundationPlaceholderTracksCanfieldBaseRank() {
        let session = SolitaireViewModel(variant: .canfield)
        guard let baseRank = CanfieldGameRules.baseRank(in: session.state) else {
            return XCTFail("a fresh Canfield deal seeds a base card")
        }
        XCTAssertEqual(session.topRowSnapshot.foundationPlaceholder, .baseRank(baseRank))

        var state = session.state
        state.foundations = Array(repeating: [], count: 4)
        session.state = state
        XCTAssertEqual(session.topRowSnapshot.foundationPlaceholder, .blank)
    }

    func testStockRecyclesRemainingIsPyramidOnly() {
        XCTAssertNotNil(SolitaireViewModel(variant: .pyramid).topRowSnapshot.stockRecyclesRemaining)
        XCTAssertNil(SolitaireViewModel(variant: .klondike).topRowSnapshot.stockRecyclesRemaining)
        XCTAssertNil(SolitaireViewModel(variant: .canfield).topRowSnapshot.stockRecyclesRemaining)
    }
}
