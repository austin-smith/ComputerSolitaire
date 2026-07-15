import SwiftUI

struct YukonTopRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let board: TopRowSnapshot
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let activeTarget: DropTarget?
    let hintedTarget: DropTarget?
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            // Yukon has no stock, waste, or free cells; keep the foundations aligned
            // over tableau columns 4-7, matching their Klondike positions.
            ForEach(0..<3, id: \.self) { _ in
                Color.clear
                    .frame(width: cardSize.width, height: cardSize.height)
                    .accessibilityHidden(true)
            }

            ForEach(0..<4, id: \.self) { index in
                FoundationView(
                    session: session,
                    pile: board.foundations.indices.contains(index) ? board.foundations[index] : nil,
                    index: index,
                    placeholder: board.foundationPlaceholder,
                    selection: selection,
                    cardSize: cardSize,
                    isTargeted: activeTarget == .foundation(index),
                    isHintTargeted: hintedTarget == .foundation(index),
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    dragGesture: dragGesture
                )
                .frame(width: cardSize.width, alignment: .leading)
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}
