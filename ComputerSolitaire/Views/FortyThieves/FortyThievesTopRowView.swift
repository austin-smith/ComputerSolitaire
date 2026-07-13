import SwiftUI
import Observation

struct FortyThievesTopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let wasteFanSpacing: CGFloat
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
            // Stock and waste on the left like Klondike's, then the eight
            // foundations — two per suit — aligned over tableau columns 3-10.
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
                fanSpacing: wasteFanSpacing,
                isHintTargeted: isWasteHinted,
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

            // Iterate the piles the state actually holds, not a fixed 0..<8:
            // during a game switch this row can re-evaluate against the
            // incoming variant's four-foundation state before the board
            // replaces it.
            ForEach(viewModel.state.foundations.indices, id: \.self) { index in
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
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}
