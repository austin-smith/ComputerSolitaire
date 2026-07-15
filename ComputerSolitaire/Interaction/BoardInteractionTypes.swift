import SwiftUI

nonisolated enum DropTarget: Hashable {
    case foundation(Int)
    case tableau(Int)
    case freeCell(Int)
    case pyramid(Int)
    case waste
    case discard
}

nonisolated enum DragOrigin: Hashable {
    case waste
    case foundation(Int)
    case freeCell(Int)
    case tableau(pile: Int, index: Int)
    case pyramid(Int)
    case triPeaks(Int)
    case reserve
}

nonisolated struct DropTargetGeometry: Equatable {
    let snapFrame: CGRect
    let hitFrame: CGRect
}

nonisolated enum DropTargetHitArea {
    static let freeCellHorizontalGrace: CGFloat = 16
    static let freeCellTopGrace: CGFloat = 14
    static let freeCellBottomGrace: CGFloat = 18

    static let foundationHorizontalGrace: CGFloat = 16
    static let foundationTopGrace: CGFloat = 14
    static let foundationBottomGrace: CGFloat = 18

    static let tableauHorizontalGrace: CGFloat = 24
    static let tableauTopGrace: CGFloat = 20
    static let tableauBottomGrace: CGFloat = 24

    // Pyramid slots overlap their neighbors, so their grace stays small to keep
    // adjacent cards distinguishable as targets.
    static let pyramidHorizontalGrace: CGFloat = 8
    static let pyramidTopGrace: CGFloat = 8
    static let pyramidBottomGrace: CGFloat = 8
}

nonisolated extension CGRect {
    func expanded(horizontal: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect {
        CGRect(
            x: minX - horizontal,
            y: minY - top,
            width: width + (horizontal * 2),
            height: height + top + bottom
        )
    }
}

nonisolated enum UndoAnimationEndTarget {
    case card(UUID)
    case stock(Int)
}
