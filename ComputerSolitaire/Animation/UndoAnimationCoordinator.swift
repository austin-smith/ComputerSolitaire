import CoreGraphics
import Foundation

struct UndoAnimationItem: Identifiable {
    let id: UUID
    let card: Card
    let startFrame: CGRect
    let endFrame: CGRect
}

enum UndoAnimationCoordinator {
    struct Cards {
        let before: [UUID: Card]
        let after: [UUID: Card]

        func card(for id: UUID, preferringAfter: Bool = false) -> Card? {
            preferringAfter ? after[id] ?? before[id] : before[id] ?? after[id]
        }
    }

    struct Frames {
        let cards: [UUID: CGRect]
        let stock: CGRect
        let waste: CGRect
    }

    struct Plan {
        let items: [UndoAnimationItem]
        let targets: [UUID: UndoAnimationEndTarget]
        let needsPostUndoFrames: Bool
    }

    static func buildPlan(
        context: UndoAnimationContext,
        cards: Cards,
        frames: Frames
    ) -> Plan {
        switch context.action {
        case .moveSelection:
            return moveSelectionPlan(cardIDs: context.cardIDs, cards: cards, frames: frames)

        case .drawFromStock:
            return drawFromStockPlan(cardIDs: context.cardIDs, cards: cards, frames: frames)

        case .recycleWaste:
            return recycleWastePlan(cardIDs: context.cardIDs, cards: cards, frames: frames)

        case .flipTableauTop:
            return Plan(items: [], targets: [:], needsPostUndoFrames: false)
        }
    }

    private static func moveSelectionPlan(cardIDs: [UUID], cards: Cards, frames: Frames) -> Plan {
        var items: [UndoAnimationItem] = []
        var targets: [UUID: UndoAnimationEndTarget] = [:]
        for id in cardIDs {
            guard let card = cards.card(for: id), let startFrame = frames.cards[id] else { continue }
            items.append(item(id: id, card: card, startFrame: startFrame))
            targets[id] = .card(id)
        }
        return Plan(items: items, targets: targets, needsPostUndoFrames: true)
    }

    private static func drawFromStockPlan(cardIDs: [UUID], cards: Cards, frames: Frames) -> Plan {
        var items: [UndoAnimationItem] = []
        var targets: [UUID: UndoAnimationEndTarget] = [:]
        for (index, id) in cardIDs.enumerated() {
            guard let card = cards.card(for: id) else { continue }
            let startFrame = frames.cards[id] ?? wasteAnchorFrame(
                for: index,
                totalCards: cardIDs.count,
                stockFrame: frames.stock,
                wasteFrame: frames.waste
            )
            guard let startFrame else { continue }
            items.append(item(id: id, card: card, startFrame: startFrame))
            targets[id] = .stock(index)
        }
        return Plan(items: items, targets: targets, needsPostUndoFrames: false)
    }

    private static func recycleWastePlan(cardIDs: [UUID], cards: Cards, frames: Frames) -> Plan {
        var items: [UndoAnimationItem] = []
        var targets: [UUID: UndoAnimationEndTarget] = [:]
        for (index, id) in cardIDs.enumerated() {
            guard let card = cards.card(for: id, preferringAfter: true),
                  let startFrame = stockAnchorFrame(for: index, stockFrame: frames.stock) else {
                continue
            }
            items.append(item(id: id, card: card, startFrame: startFrame))
            targets[id] = .card(id)
        }
        return Plan(items: items, targets: targets, needsPostUndoFrames: true)
    }

    private static func item(id: UUID, card: Card, startFrame: CGRect) -> UndoAnimationItem {
        UndoAnimationItem(id: id, card: card, startFrame: startFrame, endFrame: startFrame)
    }

    static func resolveTargetFrame(
        _ target: UndoAnimationEndTarget,
        cardFrames: [UUID: CGRect],
        stockFrame: CGRect
    ) -> CGRect? {
        switch target {
        case .card(let cardID):
            return cardFrames[cardID]
        case .stock(let index):
            return stockAnchorFrame(for: index, stockFrame: stockFrame)
        }
    }

    static func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let epsilon: CGFloat = 0.5
        return abs(lhs.minX - rhs.minX) < epsilon &&
            abs(lhs.minY - rhs.minY) < epsilon &&
            abs(lhs.width - rhs.width) < epsilon &&
            abs(lhs.height - rhs.height) < epsilon
    }

    static func stockAnchorFrame(for index: Int, stockFrame: CGRect) -> CGRect? {
        guard stockFrame != .zero else { return nil }
        let horizontalOffset = CGFloat(index) * 0.8
        let verticalOffset = CGFloat(index) * 0.5
        return stockFrame.offsetBy(dx: horizontalOffset, dy: verticalOffset)
    }

    static func wasteAnchorFrame(
        for index: Int,
        totalCards: Int,
        stockFrame: CGRect,
        wasteFrame: CGRect
    ) -> CGRect? {
        guard wasteFrame != .zero else { return nil }
        let baseWidth = stockFrame.width > 0 ? stockFrame.width : wasteFrame.height / 1.45
        let baseHeight = stockFrame.height > 0 ? stockFrame.height : wasteFrame.height
        let fanSpacing = baseWidth * 0.25
        let rightBias = max(0, totalCards - 1 - index)
        let horizontalPosition = wasteFrame.minX + CGFloat(rightBias) * fanSpacing
        return CGRect(x: horizontalPosition, y: wasteFrame.minY, width: baseWidth, height: baseHeight)
    }
}
