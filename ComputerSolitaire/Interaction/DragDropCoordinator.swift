import CoreGraphics

enum DragDropCoordinator {
    static func resolveDropTarget(
        at location: CGPoint,
        dropFrames: [DropTarget: DropTargetGeometry],
        canDrop: (DropTarget) -> Bool
    ) -> DropTarget? {
        let candidates = dropFrames.compactMap { target, geometry -> (target: DropTarget, canDrop: Bool, distanceSquared: CGFloat)? in
            guard geometry.hitFrame.contains(location) else { return nil }
            let allowed = canDrop(target)
            let dx = geometry.snapFrame.midX - location.x
            let dy = geometry.snapFrame.midY - location.y
            return (target: target, canDrop: allowed, distanceSquared: dx * dx + dy * dy)
        }

        guard !candidates.isEmpty else { return nil }

        return candidates
            .sorted { lhs, rhs in
                if lhs.canDrop != rhs.canDrop {
                    return lhs.canDrop && !rhs.canDrop
                }
                if lhs.distanceSquared != rhs.distanceSquared {
                    return lhs.distanceSquared < rhs.distanceSquared
                }
                return dropTargetSortKey(lhs.target) < dropTargetSortKey(rhs.target)
            }
            .first?
            .target
    }

    static func dropTargetSortKey(_ target: DropTarget) -> Int {
        switch target {
        case .foundation(let index):
            return index
        case .tableau(let index):
            return 100 + index
        }
    }
}
