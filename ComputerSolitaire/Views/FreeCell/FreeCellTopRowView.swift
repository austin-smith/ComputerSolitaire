import SwiftUI
import Observation

struct FreeCellTopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
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
        let middleGap = columnSpacing * 2
        let innerGap = max(0, ((7 * columnSpacing) - middleGap) / 6)
        let groupWidth = (cardSize.width * 4) + (innerGap * 3)

        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: innerGap) {
                ForEach(0..<4, id: \.self) { index in
                    FreeCellView(
                        viewModel: viewModel,
                        index: index,
                        cardSize: cardSize,
                        isTargeted: activeTarget == .freeCell(index),
                        isHintTargeted: hintedTarget == .freeCell(index),
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
            .frame(width: groupWidth, alignment: .leading)

            Color.clear
                .frame(width: middleGap, height: cardSize.height)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: innerGap) {
                ForEach(0..<4, id: \.self) { index in
                    FoundationView(
                        viewModel: viewModel,
                        index: index,
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
            .frame(width: groupWidth, alignment: .leading)
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}
