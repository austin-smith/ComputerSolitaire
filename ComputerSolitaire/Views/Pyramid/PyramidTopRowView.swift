import SwiftUI

struct PyramidTopRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let board: TopRowSnapshot
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let activeTarget: DropTarget?
    let hintedTarget: DropTarget?
    let isStockHinted: Bool
    let isWasteHinted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            StockView(
                session: session,
                stockCount: board.stockCount,
                canInteract: board.canInteractWithStock,
                recyclesRemaining: board.stockRecyclesRemaining,
                cardSize: cardSize,
                isHintTargeted: isStockHinted,
                hintHighlightOpacity: hintHighlightOpacity,
                hintWiggleToken: hintWiggleToken
            )
            .frame(width: cardSize.width, alignment: .leading)

            WasteView(
                session: session,
                cards: board.visibleWasteCards,
                selection: selection,
                cardSize: cardSize,
                fanSpacing: 0,
                isTargeted: activeTarget == .waste,
                isHintTargeted: hintedTarget == .waste || isWasteHinted,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hiddenCardIDs: hiddenCardIDs,
                hintedCardIDs: hintedCardIDs,
                hintWiggleToken: hintWiggleToken,
                drawingCardIDs: drawingCardIDs,
                fanProgress: fanProgress,
                dragGesture: dragGesture
            )
            .frame(width: cardSize.width, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("board"))
                    let hitFrame = frame.expanded(
                        horizontal: DropTargetHitArea.foundationHorizontalGrace,
                        top: DropTargetHitArea.foundationTopGrace,
                        bottom: DropTargetHitArea.foundationBottomGrace
                    )
                    Color.clear
                        .preference(
                            key: DropTargetFrameKey.self,
                            value: [
                                .waste: DropTargetGeometry(snapFrame: frame, hitFrame: hitFrame)
                            ]
                        )
                }
            )

            // Keep the discard aligned over the last tableau column, mirroring
            // where the other variants park their rightmost foundation.
            ForEach(0..<4, id: \.self) { _ in
                Color.clear
                    .frame(width: cardSize.width, height: cardSize.height)
                    .accessibilityHidden(true)
            }

            PyramidDiscardView(
                discard: board.discard,
                cardSize: cardSize,
                isTargeted: activeTarget == .discard,
                isHintTargeted: hintedTarget == .discard,
                hintHighlightOpacity: hintHighlightOpacity,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hiddenCardIDs: hiddenCardIDs
            )
            .frame(width: cardSize.width, alignment: .leading)
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}
