import SwiftUI
import Observation

struct TriPeaksTopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
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
                viewModel: viewModel,
                cardSize: cardSize,
                isHintTargeted: isStockHinted,
                hintHighlightOpacity: hintHighlightOpacity,
                hintWiggleToken: hintWiggleToken
            )
            .frame(width: cardSize.width, alignment: .leading)

            WasteView(
                viewModel: viewModel,
                cardSize: cardSize,
                fanSpacing: 0,
                isTargeted: activeTarget == .waste,
                isTapEnabled: false,
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

            // Fill the ten-column board width so the stock and waste align
            // with the leftmost peak columns.
            ForEach(0..<(TriPeaksGeometry.baseRowLength - 2), id: \.self) { _ in
                Color.clear
                    .frame(width: cardSize.width, height: cardSize.height)
                    .accessibilityHidden(true)
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}
