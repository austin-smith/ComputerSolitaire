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
        let totalDelay: Double
    }

    static func makeDrawPlan(
        newCards: [Card],
        cardSize: CGSize,
        stockFrame: CGRect,
        wasteFrame: CGRect
    ) -> Plan? {
        guard !newCards.isEmpty else { return nil }
        guard stockFrame != .zero, wasteFrame != .zero else { return nil }

        let startPoint = CGPoint(x: stockFrame.midX, y: stockFrame.midY)
        let baseX = wasteFrame.minX + cardSize.width * 0.5
        let baseY = wasteFrame.minY + cardSize.height * 0.5
        let items = newCards.enumerated().map { index, card in
            DrawAnimationCard(
                id: card.id,
                card: card,
                start: startPoint,
                end: CGPoint(x: baseX, y: baseY),
                delay: 0.05 * Double(index)
            )
        }

        return Plan(
            cards: items,
            cardIDs: Set(items.map(\.id)),
            token: UUID(),
            travelDuration: 0.32,
            totalDelay: 0.05 * Double(max(0, newCards.count - 1))
        )
    }
}
