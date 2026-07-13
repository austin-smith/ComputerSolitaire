import CoreGraphics
import Foundation

/// Builds the forward flight for a stock-onto-tableau deal (Spider's ten-card
/// row, Scorpion's three-card stock): overlay cards leave the stock in pile
/// order, flip face up in the air, and land on their piles' tops. The mirror
/// of `UndoAnimationCoordinator`'s `.dealTableauRow` flight, which flies the
/// same cards back to the same stock anchors.
enum DealAnimationCoordinator {
    struct Plan {
        let cards: [DrawAnimationCard]
        let cardIDs: Set<UUID>
        let token: UUID
        let travelDuration: Double
        /// Spring tail after the nominal travel time; the overlay comes down
        /// once the cards have visibly settled.
        let settleDuration: Double
        /// The last card's takeoff delay; the whole deal is done after
        /// `maxDelay + travelDuration + settleDuration`.
        let maxDelay: Double
    }

    /// Per-card takeoff stagger: the packet leaves the stock as one quick
    /// left-to-right sweep, reading as a deal rather than simultaneous pops.
    static let staggerInterval: Double = 0.05

    /// `dealtCards` in pile order (leftmost pile's card first). Cards without
    /// a published frame — a card banked the instant it landed — are skipped;
    /// they surface through the banking animation instead.
    static func makeDealPlan(
        dealtCards: [Card],
        cardFrames: [UUID: CGRect],
        stockFrame: CGRect
    ) -> Plan? {
        guard !dealtCards.isEmpty, stockFrame != .zero else { return nil }

        var items: [DrawAnimationCard] = []
        for (index, card) in dealtCards.enumerated() {
            guard let startFrame = UndoAnimationCoordinator.stockAnchorFrame(
                for: index,
                stockFrame: stockFrame
            ),
                let endFrame = cardFrames[card.id] else {
                continue
            }
            items.append(
                DrawAnimationCard(
                    id: card.id,
                    card: card,
                    start: CGPoint(x: startFrame.midX, y: startFrame.midY),
                    end: CGPoint(x: endFrame.midX, y: endFrame.midY),
                    delay: staggerInterval * Double(index)
                )
            )
        }
        guard !items.isEmpty else { return nil }

        return Plan(
            cards: items,
            cardIDs: Set(items.map(\.id)),
            token: UUID(),
            travelDuration: 0.32,
            settleDuration: 0.12,
            maxDelay: items.last?.delay ?? 0
        )
    }
}
