import CoreGraphics
import Foundation

struct BoardWipeCard: Identifiable {
    let id: UUID
    let card: Card
    let size: CGSize
    let start: CGPoint
    /// How far behind the palm's leading edge this card rides once caught;
    /// small offsets fan the clump instead of stacking it into one pixel.
    let rideOffset: CGFloat
    /// Vertical push the card picks up as it's carried.
    let wobble: CGFloat
    /// Tilt the card picks up as it's carried.
    let rotationDegrees: Double
}

/// Builds the clear-the-table sweep that precedes a fresh deal: a palm
/// lands at the board's left edge and wipes across, accelerating as it
/// goes. Cards are caught where they rest and then ride the palm's front,
/// piling into a clump that grows as the stroke crosses and carries the
/// whole board off the right edge. The stock never wipes: it is the deck
/// the next deal comes from (and it publishes no card frames, so it is
/// excluded by construction).
enum BoardWipeCoordinator {
    struct Plan {
        let cards: [BoardWipeCard]
        let token: UUID
        /// How far the palm's front travels over the stroke; far enough to
        /// shove the whole clump past the right edge.
        let sweepSpan: CGFloat
    }

    /// One stroke, plant to follow-through. The overlay's animation and the
    /// teardown completion both read this single constant.
    static let strokeDuration: Double = 0.45

    /// The palm's position along the stroke: quadratic in time, so the
    /// stroke plants slowly and whips through the far side. Drive it with
    /// linear progress; the acceleration lives here.
    static func frontPosition(progress: CGFloat, sweepSpan: CGFloat) -> CGFloat {
        sweepSpan * progress * progress
    }

    /// A card's rightward displacement at `progress`: zero until the palm's
    /// front reaches its resting spot, then pinned to the front (less its
    /// ride offset) — which is what piles caught cards into one traveling
    /// clump instead of letting each glide off alone.
    static func sweptDisplacement(
        progress: CGFloat,
        startX: CGFloat,
        rideOffset: CGFloat,
        sweepSpan: CGFloat
    ) -> CGFloat {
        max(0, frontPosition(progress: progress, sweepSpan: sweepSpan) - rideOffset - startX)
    }

    static func makeWipePlan(
        cards: [Card],
        cardFrames: [UUID: CGRect],
        boardSize: CGSize
    ) -> Plan? {
        guard boardSize != .zero else { return nil }
        let framed = cards
            .compactMap { card -> (card: Card, frame: CGRect)? in
                guard let frame = cardFrames[card.id] else { return nil }
                return (card, frame)
            }
            .sorted {
                // Draw order IS stacking order, and it must reproduce the
                // board's: overlapping rows (TriPeaks, Pyramid) and fanned
                // piles both render lower-on-screen cards on top, so sort
                // y-major — an x-major order flips who's on top along every
                // overlapped edge the instant the overlay stands in.
                ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX)
            }
        guard !framed.isEmpty else { return nil }

        let maxCardWidth = framed.map(\.frame.width).max() ?? 0
        let items = framed.enumerated().map { index, item -> BoardWipeCard in
            // Deterministic per-card jostle, so the clump reads as shoved
            // cards rather than a block — without randomness that would
            // make tests and resumes flaky.
            BoardWipeCard(
                id: item.card.id,
                card: item.card,
                size: item.frame.size,
                start: CGPoint(x: item.frame.midX, y: item.frame.midY),
                rideOffset: CGFloat(index % 6) * item.frame.width * 0.12,
                wobble: CGFloat((index % 5) - 2) * 10,
                rotationDegrees: Double((index % 9) - 4) * 3
            )
        }

        return Plan(
            cards: items,
            token: UUID(),
            // Far enough that the front clears the board plus the deepest
            // ride offset plus a full card — everything ends off-screen.
            sweepSpan: boardSize.width + maxCardWidth * 2.5
        )
    }
}
