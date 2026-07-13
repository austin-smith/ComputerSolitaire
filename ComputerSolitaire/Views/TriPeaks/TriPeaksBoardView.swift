import SwiftUI
import Observation

/// The 28-slot three-peak layout replaces the shared tableau row for the
/// TriPeaks variant: three face-down rows overlapping down to the face-up
/// ten-card base row. Slots are never drop targets — cards play from here onto
/// the waste — so the board registers no drop frames.
struct TriPeaksBoardView: View {
    @Bindable var viewModel: SolitaireViewModel
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
            ForEach(0..<TriPeaksGeometry.cardCount, id: \.self) { index in
                if let card = viewModel.state.triPeaks[index] {
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
        let isDragged = viewModel.isDragging && viewModel.isSelected(card: card)
        let isHidden = hiddenCardIDs.contains(card.id)
        let isSelected = viewModel.isSelected(card: card)
        let isUncovered = TriPeaksGeometry.isUncovered(index, in: viewModel.state.triPeaks)
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
            viewModel.handleTriPeaksTap(index: index)
        }
        .gesture(dragGesture(.triPeaks(index)))
        .accessibilityHidden(!isAccessibilityElement)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Plays onto the waste")
        .cardFramePreference(card.id, xOffset: offset.width, yOffset: offset.height)
    }
}
