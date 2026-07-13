import CoreGraphics
import Foundation

struct UndoAnimationItem: Identifiable {
    let id: UUID
    /// The card as it should render at the current flight phase. Plans build
    /// items with the pre-undo face; when the flight starts, the driver swaps
    /// in `endFaceUp` so the card visibly flips in the air — the mirror of the
    /// forward deal/draw flights — instead of snapping faces on landing.
    let card: Card
    let endFaceUp: Bool
    let startFrame: CGRect
    let endFrame: CGRect
}

enum UndoAnimationCoordinator {
    struct Plan {
        let items: [UndoAnimationItem]
        let targets: [UUID: UndoAnimationEndTarget]
        let needsPostUndoFrames: Bool
    }

    static func buildPlan(
        context: UndoAnimationContext,
        beforeCards: [UUID: Card],
        afterCards: [UUID: Card],
        cardFrames: [UUID: CGRect],
        stockFrame: CGRect,
        wasteFrame: CGRect
    ) -> Plan {
        var items: [UndoAnimationItem] = []
        var targets: [UUID: UndoAnimationEndTarget] = [:]
        let cardIDs = context.cardIDs

        func endFaceUp(_ id: UUID, fallback: Card) -> Bool {
            (afterCards[id] ?? fallback).isFaceUp
        }

        switch context.action {
        case .moveSelection:
            for id in cardIDs {
                guard let card = beforeCards[id] ?? afterCards[id], let startFrame = cardFrames[id] else { continue }
                items.append(UndoAnimationItem(
                    id: id,
                    card: card,
                    endFaceUp: endFaceUp(id, fallback: card),
                    startFrame: startFrame,
                    endFrame: startFrame
                ))
                targets[id] = .card(id)
            }
            return Plan(items: items, targets: targets, needsPostUndoFrames: true)

        case .drawFromStock:
            for (index, id) in cardIDs.enumerated() {
                guard let card = beforeCards[id] ?? afterCards[id] else { continue }
                guard let startFrame = cardFrames[id] ?? wasteAnchorFrame(
                    for: index,
                    totalCards: cardIDs.count,
                    stockFrame: stockFrame,
                    wasteFrame: wasteFrame
                ) else {
                    continue
                }
                items.append(UndoAnimationItem(
                    id: id,
                    card: card,
                    endFaceUp: endFaceUp(id, fallback: card),
                    startFrame: startFrame,
                    endFrame: startFrame
                ))
                targets[id] = .stock(index)
            }
            return Plan(items: items, targets: targets, needsPostUndoFrames: false)

        case .recycleWaste:
            // These cards sit face down on the stock when the flight begins,
            // so the pre-undo face keeps the takeoff honest; they flip face up
            // in the air on their way back to the waste.
            for (index, id) in cardIDs.enumerated() {
                guard let card = beforeCards[id] ?? afterCards[id],
                      let startFrame = stockAnchorFrame(for: index, stockFrame: stockFrame) else {
                    continue
                }
                items.append(UndoAnimationItem(
                    id: id,
                    card: card,
                    endFaceUp: endFaceUp(id, fallback: card),
                    startFrame: startFrame,
                    endFrame: startFrame
                ))
                targets[id] = .card(id)
            }
            return Plan(items: items, targets: targets, needsPostUndoFrames: true)

        case .dealTableauRow:
            // Spider's dealt row flies from the tableau (or a banked run's pile)
            // back onto the stock; unlike a waste draw there is no fan position
            // to fall back to when a card's frame is unknown.
            for (index, id) in cardIDs.enumerated() {
                guard let card = beforeCards[id] ?? afterCards[id],
                      let startFrame = cardFrames[id] else { continue }
                items.append(UndoAnimationItem(
                    id: id,
                    card: card,
                    endFaceUp: endFaceUp(id, fallback: card),
                    startFrame: startFrame,
                    endFrame: startFrame
                ))
                targets[id] = .stock(index)
            }
            return Plan(items: items, targets: targets, needsPostUndoFrames: false)

        case .flipTableauTop:
            return Plan(items: [], targets: [:], needsPostUndoFrames: false)
        }
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
        let dx = CGFloat(index) * 0.8
        let dy = CGFloat(index) * 0.5
        return stockFrame.offsetBy(dx: dx, dy: dy)
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
        let x = wasteFrame.minX + CGFloat(rightBias) * fanSpacing
        return CGRect(x: x, y: wasteFrame.minY, width: baseWidth, height: baseHeight)
    }
}
