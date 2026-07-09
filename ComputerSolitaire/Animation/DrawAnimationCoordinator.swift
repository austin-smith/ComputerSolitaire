import CoreGraphics
import Foundation

struct DrawAnimationCard: Identifiable {
    let id: UUID
    let card: Card
    let start: CGPoint
    let end: CGPoint
    let delay: Double
}

enum DrawAnimationCoordinator {
    struct Plan {
        let cards: [DrawAnimationCard]
        let cardIDs: Set<UUID>
        let token: UUID
        let travelDuration: Double
        /// Spring tail after the nominal travel time; the overlay comes down
        /// once the cards have visibly settled.
        let settleDuration: Double
    }

    static func makeDrawPlan(
        newCards: [Card],
        cardSize: CGSize,
        stockFrame: CGRect,
        wasteFrame: CGRect,
        fanSpacing: CGFloat
    ) -> Plan? {
        guard !newCards.isEmpty else { return nil }
        guard stockFrame != .zero, wasteFrame != .zero else { return nil }

        let startPoint = CGPoint(x: stockFrame.midX, y: stockFrame.midY)
        let baseX = wasteFrame.minX + cardSize.width * 0.5
        let baseY = wasteFrame.minY + cardSize.height * 0.5
        // One gesture: the packet leaves the stock together and each card
        // flies straight to its own fan slot, flipping in the air on the way
        // — so the spread opens up mid-flight and they land already fanned.
        let items = newCards.enumerated().map { index, card in
            DrawAnimationCard(
                id: card.id,
                card: card,
                start: startPoint,
                end: CGPoint(x: baseX + fanSpacing * CGFloat(index), y: baseY),
                delay: 0
            )
        }

        return Plan(
            cards: items,
            cardIDs: Set(items.map(\.id)),
            token: UUID(),
            travelDuration: 0.32,
            settleDuration: 0.12
        )
    }
}
