import SwiftUI

/// The 28-slot three-peak layout replaces the shared tableau row for the
/// TriPeaks variant: three face-down rows overlapping down to the face-up
/// ten-card base row. Slots are never drop targets — cards play from here onto
/// the waste — so the board registers no drop frames.
struct TriPeaksBoardView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let triPeaks: [Card?]
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let maxBoardHeight: CGFloat
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let rowOverlap = rowOverlap
        let boardWidth = (cardSize.width * CGFloat(TriPeaksGeometry.baseRowLength))
            + (columnSpacing * CGFloat(TriPeaksGeometry.baseRowLength - 1))
        let boardHeight = cardSize.height + rowOverlap * CGFloat(TriPeaksGeometry.rowCount - 1)

        ZStack(alignment: .topLeading) {
            // Iterate the slots the state actually holds, not a fixed
            // 0..<28: during a game switch this view can re-evaluate against
            // the incoming variant's empty triPeaks array before the board
            // replaces it.
            ForEach(Array(triPeaks.enumerated()), id: \.offset) { index, slot in
                if let card = slot {
                    peakCard(card, at: index, rowOverlap: rowOverlap)
                }
            }
        }
        .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }

    /// Vertical distance between rows: cards naturally show their top ~45%, and
    /// compress toward 30% when the board height budget is tight.
    private var rowOverlap: CGFloat {
        let naturalOverlap = cardSize.height * 0.55
        let fittedOverlap = (maxBoardHeight - cardSize.height) / CGFloat(TriPeaksGeometry.rowCount - 1)
        return min(naturalOverlap, max(cardSize.height * 0.3, fittedOverlap))
    }

    private func slotOffset(for index: Int, rowOverlap: CGFloat) -> CGSize {
        CGSize(
            width: TriPeaksGeometry.columnOffsetUnits(of: index)
                * (cardSize.width + columnSpacing) / 2,
            height: CGFloat(TriPeaksGeometry.row(of: index)) * rowOverlap
        )
    }

    @ViewBuilder
    private func peakCard(_ card: Card, at index: Int, rowOverlap: CGFloat) -> some View {
        let row = TriPeaksGeometry.row(of: index)
        let offset = slotOffset(for: index, rowOverlap: rowOverlap)
        let isDragged = selection.isDragging && selection.isSelected(card)
        let isHidden = hiddenCardIDs.contains(card.id)
        let isSelected = selection.isSelected(card)
        let isUncovered = TriPeaksGeometry.isUncovered(index, in: triPeaks)
        let isAccessibilityElement = card.isFaceUp && isUncovered && !isDragged && !isHidden

        CardView(
            card: card,
            isSelected: isSelected,
            cardSize: cardSize,
            isCardTiltEnabled: isCardTiltEnabled,
            cardTilts: $cardTilts,
            hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil,
            isAccessibilityElement: isAccessibilityElement
        )
        .opacity(isDragged || isHidden ? 0 : 1)
        .offset(x: offset.width, y: offset.height)
        .zIndex(isDragged ? 40 + Double(row) : Double(row))
        .allowsHitTesting(!isHidden)
        .onTapGesture {
            session.handleTriPeaksTap(index: index)
        }
        .gesture(dragGesture(.triPeaks(index)))
        .accessibilityHidden(!isAccessibilityElement)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Plays onto the waste")
        .cardFramePreference(card.id, xOffset: offset.width, yOffset: offset.height)
    }
}

/// See TableauPileView's Equatable note for the exclusion contract.
extension TriPeaksBoardView: Equatable {
    nonisolated static func == (lhs: TriPeaksBoardView, rhs: TriPeaksBoardView) -> Bool {
        lhs.session === rhs.session
            && lhs.triPeaks == rhs.triPeaks
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.columnSpacing == rhs.columnSpacing
            && lhs.maxBoardHeight == rhs.maxBoardHeight
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}
