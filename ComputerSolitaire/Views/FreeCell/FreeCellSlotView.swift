import SwiftUI

struct FreeCellView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let card: Card?
    let index: Int
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let isTargeted: Bool
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let accessibleCard: Card? = card.flatMap { card in
            let isHidden = hiddenCardIDs.contains(card.id)
            let isDragged = selection.isDragging && selection.isSelected(card)
            return isHidden || isDragged ? nil : card
        }
        let isAccessibleCardSelected = accessibleCard.map {
            selection.isSelected($0)
        } ?? false
        let isDragSource: Bool = {
            if case .freeCell(let slot) = selection.dragSource {
                return slot == index
            }
            return false
        }()

        ZStack {
            PilePlaceholderView(cardSize: cardSize)
            DropHighlightView(
                cardSize: cardSize,
                isTargeted: isTargeted,
                isHintTargeted: isHintTargeted,
                hintOpacity: hintHighlightOpacity
            )
            if let card {
                CardView(
                    card: card,
                    isSelected: selection.isSelected(card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil,
                    isAccessibilityElement: false
                )
                .opacity(
                    (selection.isDragging && selection.isSelected(card))
                        || hiddenCardIDs.contains(card.id) ? 0 : 1
                )
                .gesture(dragGesture(.freeCell(index)))
                .cardFramePreference(card.id)
            }
        }
        .onTapGesture {
            session.handleFreeCellTap(index: index)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isAccessibleCardSelected ? .isSelected : [])
        .background(
            GeometryReader { proxy in
                let boardFrame = proxy.frame(in: .named("board"))
                let hitFrame = boardFrame.expanded(
                    horizontal: DropTargetHitArea.freeCellHorizontalGrace,
                    top: DropTargetHitArea.freeCellTopGrace,
                    bottom: DropTargetHitArea.freeCellBottomGrace
                )
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .freeCell(index): DropTargetGeometry(
                                snapFrame: boardFrame,
                                hitFrame: hitFrame
                            )
                        ]
                    )
            }
        )
        .zIndex(isDragSource ? 10 : 0)
        .accessibilityLabel("Free Cell \(index + 1)")
        .accessibilityValue(accessibleCard?.accessibilityName ?? "Empty")
    }
}

/// See TableauPileView's Equatable note for the exclusion contract.
extension FreeCellView: Equatable {
    nonisolated static func == (lhs: FreeCellView, rhs: FreeCellView) -> Bool {
        lhs.session === rhs.session
            && lhs.card == rhs.card
            && lhs.index == rhs.index
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.isTargeted == rhs.isTargeted
            && lhs.isHintTargeted == rhs.isHintTargeted
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}
