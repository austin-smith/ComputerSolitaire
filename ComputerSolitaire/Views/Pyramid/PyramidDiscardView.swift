import SwiftUI
import Observation

/// Where removed pairs and Kings land. Inert by design: cards here are out of
/// play, so the pile takes drops (via the shared drop targeting) but offers no
/// taps or drags of its own.
struct PyramidDiscardView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let isTargeted: Bool
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>

    var body: some View {
        let discard = viewModel.state.discard
        let visibleDepth = min(discard.count, 4)
        let startIndex = discard.count - visibleDepth

        ZStack {
            PilePlaceholderView(cardSize: cardSize)
            if discard.isEmpty {
                Image(systemName: "xmark")
                    .font(.system(size: cardSize.width * 0.22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
                    .allowsHitTesting(false)
            }
            DropHighlightView(
                cardSize: cardSize,
                isTargeted: isTargeted,
                isHintTargeted: isHintTargeted,
                hintOpacity: hintHighlightOpacity
            )
            .zIndex(1)
            ForEach(Array(discard.enumerated().dropFirst(startIndex)), id: \.element.id) { _, card in
                CardView(
                    card: card,
                    isSelected: false,
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hintWiggleToken: nil,
                    isAccessibilityElement: false
                )
                .opacity(hiddenCardIDs.contains(card.id) ? 0 : 1)
                .allowsHitTesting(false)
                .cardFramePreference(card.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discard pile")
        .accessibilityValue("\(discard.count) cards removed")
        .background(
            GeometryReader { proxy in
                let boardFrame = proxy.frame(in: .named("board"))
                let hitFrame = boardFrame.expanded(
                    horizontal: DropTargetHitArea.foundationHorizontalGrace,
                    top: DropTargetHitArea.foundationTopGrace,
                    bottom: DropTargetHitArea.foundationBottomGrace
                )
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .discard: DropTargetGeometry(
                                snapFrame: boardFrame,
                                hitFrame: hitFrame
                            )
                        ]
                    )
            }
        )
    }
}
