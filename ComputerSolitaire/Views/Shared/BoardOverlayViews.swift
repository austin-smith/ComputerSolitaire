import SwiftUI
import Observation

struct DrawOverlayView: View {
    let cards: [DrawAnimationCard]
    let cardSize: CGSize

    var body: some View {
        ForEach(cards) { item in
            DrawOverlayCardView(
                card: item.card,
                cardSize: cardSize,
                start: item.start,
                end: item.end,
                delay: item.delay
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct UndoOverlayView: View {
    let items: [UndoAnimationItem]
    let progress: CGFloat

    var body: some View {
        ForEach(items) { item in
            let currentX = item.startFrame.midX + ((item.endFrame.midX - item.startFrame.midX) * progress)
            let currentY = item.startFrame.midY + ((item.endFrame.midY - item.startFrame.midY) * progress)
            CardView(
                card: item.card,
                isSelected: false,
                cardSize: item.startFrame.size,
                isCardTiltEnabled: false,
                cardTilts: .constant([:])
            )
            .position(x: currentX, y: currentY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WinCascadeOverlayView: View {
    let cards: [WinCascadeCardState]

    var body: some View {
        ForEach(cards) { item in
            let isVisible = item.elapsed >= item.activationDelay
            CardView(
                card: item.card,
                isSelected: false,
                cardSize: item.size,
                isCardTiltEnabled: false,
                cardTilts: .constant([:])
            )
            .rotationEffect(.degrees(item.rotationDegrees))
            .position(item.position)
            .opacity(isVisible ? 1 : 0)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DrawOverlayCardView: View {
    let card: Card
    let cardSize: CGSize
    let start: CGPoint
    let end: CGPoint
    let delay: Double
    @State private var progress: CGFloat = 0

    var body: some View {
        let currentX = start.x + (end.x - start.x) * progress
        let currentY = start.y + (end.y - start.y) * progress
        CardView(
            card: card,
            isSelected: false,
            cardSize: cardSize,
            isCardTiltEnabled: false,
            cardTilts: .constant([:]),
            flipOnAppear: true,
            flipDelay: delay + 0.05
        )
        .position(x: currentX, y: currentY)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86).delay(delay)) {
                progress = 1
            }
        }
    }
}

struct DragOverlayView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardFrames: [UUID: CGRect]
    let cardTilts: [UUID: Double]
    let dragTranslation: CGSize
    let dragReturnOffset: CGSize
    let isReturningDrag: Bool
    let returningCards: [Card]
    let isDroppingCards: Bool
    let droppingCards: [Card]
    let dropAnimationOffset: CGSize
    let overlayTilt: Double

    var body: some View {
        Group {
            if isDroppingCards {
                dragCards(droppingCards, additionalOffset: dropAnimationOffset)
            } else if isReturningDrag {
                dragCards(returningCards, additionalOffset: dragReturnOffset)
            } else if viewModel.isDragging, let selection = viewModel.selection {
                dragCards(selection.cards, additionalOffset: .zero)
            }
        }
        .allowsHitTesting(false)
        .zIndex(100)
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private func dragCards(_ cards: [Card], additionalOffset: CGSize) -> some View {
        if cards.isEmpty {
            EmptyView()
        } else {
            ForEach(cards, id: \.id) { card in
                if let frame = cardFrames[card.id] {
                    CardView(
                        card: card,
                        isSelected: true,
                        cardSize: frame.size,
                        isCardTiltEnabled: false,
                        cardTilts: .constant([:])
                    )
                    .rotationEffect(.degrees(overlayTilt))
                    .position(x: frame.midX, y: frame.midY)
                    .offset(
                        x: dragTranslation.width + additionalOffset.width,
                        y: dragTranslation.height + additionalOffset.height
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)
                }
            }
        }
    }
}
