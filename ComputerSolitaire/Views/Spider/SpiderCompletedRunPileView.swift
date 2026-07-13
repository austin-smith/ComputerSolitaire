import SwiftUI

/// One of Spider's eight banked-run piles. Runs arrive here automatically, so
/// unlike `FoundationView` this pile is never a tap, drag, or drop target; it
/// still publishes its frames so the win cascade can launch cards from it.
/// The pile arrives by value — this view must stay renderable against any
/// game's state, because during a game switch it can re-evaluate after the
/// board's state has already changed variant.
struct SpiderCompletedRunPileView: View {
    let pile: [Card]
    let index: Int
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>

    var body: some View {
        let visibleDepth = min(pile.count, 4)
        let startIndex = pile.count - visibleDepth
        ZStack {
            PilePlaceholderView(cardSize: cardSize)
            ForEach(Array(pile.enumerated().dropFirst(startIndex)), id: \.element.id) { cardIndex, card in
                let isTopCard = cardIndex == pile.count - 1
                let cardView = CardView(
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

                if isTopCard {
                    cardView
                        .cardFramePreference(card.id)
                } else {
                    cardView
                }
            }
        }
        .background(
            GeometryReader { proxy in
                let boardFrame = proxy.frame(in: .named("board"))
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .foundation(index): DropTargetGeometry(
                                snapFrame: boardFrame,
                                hitFrame: .zero
                            )
                        ]
                    )
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Completed run \(index + 1)")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let topCard = pile.last else { return "Empty" }
        return "Full \(topCard.suit.accessibilityName) run"
    }
}
