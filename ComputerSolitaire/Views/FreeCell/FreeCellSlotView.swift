import SwiftUI
import Observation

struct FreeCellView: View {
    @Bindable var viewModel: SolitaireViewModel
    let index: Int
    let cardSize: CGSize
    let isTargeted: Bool
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let card = viewModel.state.freeCells[index]
        let isDragSource: Bool = {
            guard viewModel.isDragging, let selection = viewModel.selection else { return false }
            if case .freeCell(let slot) = selection.source {
                return slot == index
            }
            return false
        }()

        ZStack {
            PilePlaceholderView(cardSize: cardSize)
            DropHighlightView(
                cardSize: cardSize,
                isTargeted: isTargeted,
                isHintTargeted: isHintTargeted,
                hintOpacity: hintHighlightOpacity
            )
            if let card {
                CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil
                )
                .opacity((viewModel.isDragging && viewModel.isSelected(card: card)) || hiddenCardIDs.contains(card.id) ? 0 : 1)
                .gesture(dragGesture(.freeCell(index)))
                .cardFramePreference(card.id)
            }
        }
        .onTapGesture {
            viewModel.handleFreeCellTap(index: index)
        }
        .background(
            GeometryReader { proxy in
                let boardFrame = proxy.frame(in: .named("board"))
                let hitFrame = boardFrame.expanded(
                    horizontal: DropTargetHitArea.freeCellHorizontalGrace,
                    top: DropTargetHitArea.freeCellTopGrace,
                    bottom: DropTargetHitArea.freeCellBottomGrace
                )
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .freeCell(index): DropTargetGeometry(
                                snapFrame: boardFrame,
                                hitFrame: hitFrame
                            )
                        ]
                    )
            }
        )
        .zIndex(isDragSource ? 10 : 0)
        .accessibilityLabel("Free Cell \(index + 1)")
    }
}
