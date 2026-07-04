import SwiftUI

enum DropTarget: Hashable {
    case foundation(Int)
    case tableau(Int)
    case freeCell(Int)
}

enum DragOrigin: Hashable {
    case waste
    case foundation(Int)
    case freeCell(Int)
    case tableau(pile: Int, index: Int)
}

struct DropTargetGeometry: Equatable {
    let snapFrame: CGRect
    let hitFrame: CGRect
}

enum DropTargetHitArea {
    static let freeCellHorizontalGrace: CGFloat = 16
    static let freeCellTopGrace: CGFloat = 14
    static let freeCellBottomGrace: CGFloat = 18

    static let foundationHorizontalGrace: CGFloat = 16
    static let foundationTopGrace: CGFloat = 14
    static let foundationBottomGrace: CGFloat = 18

    static let tableauHorizontalGrace: CGFloat = 24
    static let tableauTopGrace: CGFloat = 20
    static let tableauBottomGrace: CGFloat = 24
}

extension CGRect {
    func expanded(horizontal: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect {
        CGRect(
            x: minX - horizontal,
            y: minY - top,
            width: width + (horizontal * 2),
            height: height + top + bottom
        )
    }
}

enum UndoAnimationEndTarget {
    case card(UUID)
    case stock(Int)
}
