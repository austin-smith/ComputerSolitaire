import SwiftUI
import Observation

struct DrawOverlayView: View {
    let cards: [DrawAnimationCard]
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    /// Fresh-board deals queue every card on one shared anchor, so waiting
    /// cards hide until takeoff (a visible queue would peel from under the
    /// deck). Stock deals and draws keep their queues visible: their cards
    /// wait on distinct per-index anchors, covering the already-decremented
    /// stock until each departs.
    var hidesUntilTakeoff = false

    var body: some View {
        ForEach(cards) { item in
            DrawOverlayCardView(
                card: item.card,
                cardSize: cardSize,
                start: item.start,
                end: item.end,
                delay: item.delay,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hidesUntilTakeoff: hidesUntilTakeoff
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The clear-the-table sweep before a fresh deal: one palm stroke crosses
/// the board and every card rides it off the right edge, piling into a
/// traveling clump. One linear progress drives the whole stroke; the
/// acceleration and each card's catch-and-carry happen per frame inside
/// `WipeRideEffect`, because a clump only forms when positions track the
/// palm's front continuously — endpoint animation can't produce it.
struct BoardWipeOverlayView: View {
    let cards: [BoardWipeCard]
    let sweepSpan: CGFloat
    let strokeDuration: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    @Environment(\.motionPolicy) private var motion
    @State private var strokeProgress: CGFloat = 0

    var body: some View {
        Group {
            ForEach(cards) { item in
                CardView(
                    card: item.card,
                    isSelected: false,
                    cardSize: item.size,
                    // Shares the real cards' resting tilt so replacing the
                    // board with the overlay is pixel-identical — otherwise
                    // every card visibly snaps straight before the stroke.
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    isAccessibilityElement: false
                )
                .modifier(
                    WipeRideEffect(
                        progress: strokeProgress,
                        item: item,
                        sweepSpan: sweepSpan
                    )
                )
                .position(item.start)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            // Linear on purpose: the whip lives in the front's quadratic
            // curve, and the completion in ContentView scales through the
            // same policy so teardown lands after the stroke finishes.
            withAnimation(motion.linear(strokeDuration)) {
                strokeProgress = 1
            }
        }
    }
}

/// Per-frame catch-and-carry: a card stays planted until the palm's front
/// reaches it, then translates with the front, picking up its tilt and
/// vertical wobble over its first card-width of travel.
private struct WipeRideEffect: GeometryEffect {
    var progress: CGFloat
    let item: BoardWipeCard
    let sweepSpan: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = BoardWipeCoordinator.sweptDisplacement(
            progress: progress,
            startX: item.start.x,
            rideOffset: item.rideOffset,
            sweepSpan: sweepSpan
        )
        // How settled into the clump the card is: jostle ramps in over the
        // first card-width of carry, then holds.
        let carried = min(1, dx / max(size.width, 1))
        var transform = CGAffineTransform(translationX: dx, y: item.wobble * carried)
        transform = transform
            .translatedBy(x: size.width / 2, y: size.height / 2)
            .rotated(by: item.rotationDegrees * carried * .pi / 180)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
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
                cardTilts: .constant([:]),
                isAccessibilityElement: false
            )
            .position(x: currentX, y: currentY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WinCascadeOverlayView: View {
    /// The cascade task mutates `cards` every frame while cards fly; reading
    /// it here — not in ContentView — keeps the per-tick re-render confined
    /// to this overlay.
    let winCelebration: WinCelebrationController

    var body: some View {
        ForEach(winCelebration.cards) { item in
            let isVisible = item.elapsed >= item.activationDelay
            CardView(
                card: item.card,
                isSelected: false,
                cardSize: item.size,
                isCardTiltEnabled: false,
                cardTilts: .constant([:]),
                isAccessibilityElement: false
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
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hidesUntilTakeoff: Bool
    @Environment(\.motionPolicy) private var motion
    @State private var progress: CGFloat = 0
    @State private var hasTakenOff = false

    var body: some View {
        let currentX = start.x + (end.x - start.x) * progress
        let currentY = start.y + (end.y - start.y) * progress
        CardView(
            card: card,
            isSelected: false,
            cardSize: cardSize,
            // Shares the real card's tilt so the resting pose is already
            // there when the overlay hands off — no post-landing tilt pop.
            isCardTiltEnabled: isCardTiltEnabled,
            cardTilts: $cardTilts,
            flipOnAppear: true,
            // The packet flips in the air while it travels and spreads.
            flipDelay: delay,
            isAccessibilityElement: false
        )
        .position(x: currentX, y: currentY)
        // See DrawOverlayView: only fresh-board deals hide their queue.
        .opacity(!hidesUntilTakeoff || hasTakenOff ? 1 : 0)
        .onAppear {
            // Travel pace matches the coordinator plans' travelDuration; the
            // completion in ContentView scales through the same policy, so
            // the overlay always comes down after the cards have settled.
            withAnimation(motion.spring(response: 0.32, dampingFraction: 0.86)?.delay(motion.duration(delay))) {
                progress = 1
            }
            if hidesUntilTakeoff {
                // The reveal rides the same animation clock as the travel
                // spring (not a wall-clock timer): if the main thread runs
                // behind during a big board mount, both shift together and
                // a card can never be seen mid-air before it "exists".
                withAnimation(motion.linear(0.05)?.delay(motion.duration(delay))) {
                    hasTakenOff = true
                }
            }
        }
    }
}

struct DragOverlayView: View {
    @Bindable var viewModel: SolitaireViewModel
    /// The gesture's per-frame translation. Read here — and only here — so the
    /// per-frame writes re-render just this overlay, never the board tree
    /// behind it. The flight-boundary fields arrive as plain values from
    /// ContentView's `@State` so their `withAnimation` springs survive (see
    /// DragInteractionController's doc comment).
    let drag: DragInteractionController
    let cardFrames: [UUID: CGRect]
    let overlayTilt: Double
    let dragReturnOffset: CGSize
    let isReturningDrag: Bool
    let returningCards: [Card]
    let isDroppingCards: Bool
    let droppingCards: [Card]
    let dropAnimationOffset: CGSize
    let wasteReturnAnchorCardID: UUID?
    let wasteReturnAnchorFrame: CGRect?

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

    /// A waste card returning from an invalid drop flies back to the fan slot
    /// it left, not to wherever the fan has since collapsed to — the anchor
    /// frame captured at pickup overrides the card's live frame.
    private var effectiveCardFrames: [UUID: CGRect] {
        guard isReturningDrag,
              let returningCard = returningCards.first,
              returningCard.id == wasteReturnAnchorCardID,
              let anchorFrame = wasteReturnAnchorFrame else {
            return cardFrames
        }
        var frames = cardFrames
        frames[returningCard.id] = anchorFrame
        return frames
    }

    @ViewBuilder
    private func dragCards(_ cards: [Card], additionalOffset: CGSize) -> some View {
        if cards.isEmpty {
            EmptyView()
        } else {
            let frames = effectiveCardFrames
            ForEach(cards, id: \.id) { card in
                if let frame = frames[card.id] {
                    CardView(
                        card: card,
                        isSelected: true,
                        cardSize: frame.size,
                        isCardTiltEnabled: false,
                        cardTilts: .constant([:]),
                        isAccessibilityElement: false
                    )
                    .rotationEffect(.degrees(overlayTilt))
                    .position(x: frame.midX, y: frame.midY)
                    .offset(
                        x: drag.dragTranslation.width + additionalOffset.width,
                        y: drag.dragTranslation.height + additionalOffset.height
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)
                }
            }
        }
    }
}
