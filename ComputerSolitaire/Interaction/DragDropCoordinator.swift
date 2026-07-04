import CoreGraphics

enum DragDropCoordinator {
    static func resolveDropTarget(
        at location: CGPoint,
        dropFrames: [DropTarget: DropTargetGeometry],
        canDrop: (DropTarget) -> Bool
    ) -> DropTarget? {
        var bestTarget: DropTarget?
        var bestCanDrop = false
        var bestDistanceSquared = CGFloat.infinity
        var bestSortKey = Int.max

        for (target, geometry) in dropFrames {
            guard geometry.hitFrame.contains(location) else { continue }

            let candidateCanDrop = canDrop(target)
            let dx = geometry.snapFrame.midX - location.x
            let dy = geometry.snapFrame.midY - location.y
            let candidateDistanceSquared = dx * dx + dy * dy
            let candidateSortKey = dropTargetSortKey(target)

            let shouldReplaceBest: Bool
            if candidateCanDrop != bestCanDrop {
                shouldReplaceBest = candidateCanDrop && !bestCanDrop
            } else if candidateDistanceSquared != bestDistanceSquared {
                shouldReplaceBest = candidateDistanceSquared < bestDistanceSquared
            } else {
                shouldReplaceBest = candidateSortKey < bestSortKey
            }

            if shouldReplaceBest || bestTarget == nil {
                bestTarget = target
                bestCanDrop = candidateCanDrop
                bestDistanceSquared = candidateDistanceSquared
                bestSortKey = candidateSortKey
            }
        }

        return bestTarget
    }

    static func dropTargetSortKey(_ target: DropTarget) -> Int {
        switch target {
        case .freeCell(let index):
            return index
        case .foundation(let index):
            return 100 + index
        case .tableau(let index):
            return 200 + index
        }
    }
}
