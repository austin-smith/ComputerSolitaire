import SwiftUI
import Observation

/// The 28-slot pyramid replaces the shared tableau row for the Pyramid variant:
/// seven centered rows where each card half-overlaps the two cards above it.
struct PyramidBoardView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let maxBoardHeight: CGFloat
    let activeTarget: DropTarget?
    let hintedTarget: DropTarget?
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let rowOverlap = rowOverlap
        let boardWidth = (cardSize.width * CGFloat(PyramidGeometry.rowCount))
            + (columnSpacing * CGFloat(PyramidGeometry.rowCount - 1))
        let boardHeight = cardSize.height + rowOverlap * CGFloat(PyramidGeometry.rowCount - 1)

        ZStack(alignment: .topLeading) {
            // Iterate the slots the state actually holds, not a fixed
            // 0..<28: during a game switch this view can re-evaluate against
            // the incoming variant's empty pyramid before the board replaces
            // it.
            ForEach(Array(viewModel.state.pyramid.enumerated()), id: \.offset) { index, slot in
                if let card = slot {
                    pyramidCard(card, at: index, rowOverlap: rowOverlap)
                }
            }
        }
        .frame(width: boardWidth, height: boardHeight, alignment: .topLeading)
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }

    /// Vertical distance between rows: cards naturally show their top ~45%, and
    /// compress toward 30% when the board height budget is tight.
    private var rowOverlap: CGFloat {
        let naturalOverlap = cardSize.height * 0.55
        let fittedOverlap = (maxBoardHeight - cardSize.height) / CGFloat(PyramidGeometry.rowCount - 1)
        return min(naturalOverlap, max(cardSize.height * 0.3, fittedOverlap))
    }

    private func slotOffset(for index: Int, rowOverlap: CGFloat) -> CGSize {
        let row = PyramidGeometry.row(of: index)
        let column = PyramidGeometry.column(of: index)
        let columnUnits = CGFloat(PyramidGeometry.rowCount - 1 - row) / 2 + CGFloat(column)
        return CGSize(
            width: columnUnits * (cardSize.width + columnSpacing),
            height: CGFloat(row) * rowOverlap
        )
    }

    @ViewBuilder
    private func pyramidCard(_ card: Card, at index: Int, rowOverlap: CGFloat) -> some View {
        let row = PyramidGeometry.row(of: index)
        let offset = slotOffset(for: index, rowOverlap: rowOverlap)
        let isDragged = viewModel.isDragging && viewModel.isSelected(card: card)
        let isHidden = hiddenCardIDs.contains(card.id)
        let isSelected = viewModel.isSelected(card: card)
        let isSelectable = PyramidGameRules.isSelectable(index: index, in: viewModel.state.pyramid)
        let isAccessibilityElement = isSelectable && !isDragged && !isHidden
        let isTargeted = activeTarget == .pyramid(index)
        let isHintTargeted = hintedTarget == .pyramid(index)
        let accessibilityHint = card.rank == .king
            ? "Removes the King"
            : "Selects this card"

        ZStack {
            CardView(
                card: card,
                isSelected: isSelected,
                cardSize: cardSize,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil,
                isAccessibilityElement: isAccessibilityElement
            )
            DropHighlightView(
                cardSize: cardSize,
                isTargeted: isTargeted,
                isHintTargeted: isHintTargeted,
                hintOpacity: hintHighlightOpacity
            )
            .allowsHitTesting(false)
        }
        .opacity(isDragged || isHidden ? 0 : 1)
        .offset(x: offset.width, y: offset.height)
        .zIndex(isDragged ? 40 + Double(row) : Double(row))
        .allowsHitTesting(!isHidden)
        .onTapGesture {
            viewModel.handlePyramidTap(index: index)
        }
        .gesture(dragGesture(.pyramid(index)))
        .accessibilityHidden(!isAccessibilityElement)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
        .cardFramePreference(card.id, xOffset: offset.width, yOffset: offset.height)
        .background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("board"))
                let snapFrame = frame.offsetBy(dx: offset.width, dy: offset.height)
                let hitFrame = snapFrame.expanded(
                    horizontal: DropTargetHitArea.pyramidHorizontalGrace,
                    top: DropTargetHitArea.pyramidTopGrace,
                    bottom: DropTargetHitArea.pyramidBottomGrace
                )
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .pyramid(index): DropTargetGeometry(
                                snapFrame: snapFrame,
                                hitFrame: hitFrame
                            )
                        ]
                    )
            }
        )
    }
}
