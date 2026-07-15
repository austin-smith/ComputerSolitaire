import SwiftUI

/// Canfield's top row matches Klondike's shape — stock, fanned waste, a
/// spacer column the fan can overflow into, and four foundations. The
/// reserve renders in the tableau band (see `CanfieldBoardRowView`), beside
/// the piles it feeds, as on a physical table.
struct CanfieldTopRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let board: TopRowSnapshot
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let wasteFanSpacing: CGFloat
    let activeTarget: DropTarget?
    let hintedTarget: DropTarget?
    let isStockHinted: Bool
    let isWasteHinted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            StockView(
                session: session,
                stockCount: board.stockCount,
                canInteract: board.canInteractWithStock,
                recyclesRemaining: board.stockRecyclesRemaining,
                cardSize: cardSize,
                isHintTargeted: isStockHinted,
                hintHighlightOpacity: hintHighlightOpacity,
                hintWiggleToken: hintWiggleToken
            )
            .frame(width: cardSize.width, alignment: .leading)

            WasteView(
                session: session,
                cards: board.visibleWasteCards,
                selection: selection,
                cardSize: cardSize,
                fanSpacing: wasteFanSpacing,
                isHintTargeted: isWasteHinted,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hiddenCardIDs: hiddenCardIDs,
                hintedCardIDs: hintedCardIDs,
                hintWiggleToken: hintWiggleToken,
                drawingCardIDs: drawingCardIDs,
                fanProgress: fanProgress,
                dragGesture: dragGesture
            )
            // Keep top-row columns aligned with tableau; waste fan can overflow visually
            // without changing foundation positions.
            .frame(width: cardSize.width, alignment: .leading)

            Color.clear
                .frame(width: cardSize.width, height: cardSize.height)
                .accessibilityHidden(true)

            ForEach(0..<4, id: \.self) { index in
                FoundationView(
                    session: session,
                    pile: board.foundations.indices.contains(index) ? board.foundations[index] : nil,
                    index: index,
                    placeholder: board.foundationPlaceholder,
                    selection: selection,
                    cardSize: cardSize,
                    isTargeted: activeTarget == .foundation(index),
                    isHintTargeted: hintedTarget == .foundation(index),
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    dragGesture: dragGesture
                )
                .frame(width: cardSize.width, alignment: .leading)
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}

/// Canfield's tableau band: the reserve at the leftmost column — under the
/// stock, as on a physical table — a spacer pair, then the four tableau
/// piles aligned directly beneath the four foundations.
struct CanfieldBoardRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let reserve: [Card]
    let tableau: [[Card]]
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let faceDownOffset: CGFloat
    let faceUpOffset: CGFloat
    let maxPileHeight: CGFloat
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
        HStack(alignment: .top, spacing: columnSpacing) {
            CanfieldReserveView(
                session: session,
                reserve: reserve,
                selection: selection,
                cardSize: cardSize,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hiddenCardIDs: hiddenCardIDs,
                hintedCardIDs: hintedCardIDs,
                hintWiggleToken: hintWiggleToken,
                dragGesture: dragGesture
            )
            .frame(width: cardSize.width, alignment: .leading)

            ForEach(0..<2, id: \.self) { _ in
                Color.clear
                    .frame(width: cardSize.width, height: cardSize.height)
                    .accessibilityHidden(true)
            }

            TableauRowView(
                session: session,
                tableau: tableau,
                variant: .canfield,
                selection: selection,
                cardSize: cardSize,
                columnSpacing: columnSpacing,
                faceDownOffset: faceDownOffset,
                faceUpOffset: faceUpOffset,
                maxPileHeight: maxPileHeight,
                activeTarget: activeTarget,
                hintedTarget: hintedTarget,
                hintHighlightOpacity: hintHighlightOpacity,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hiddenCardIDs: hiddenCardIDs,
                hintedCardIDs: hintedCardIDs,
                hintWiggleToken: hintWiggleToken,
                dragGesture: dragGesture
            )
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}

/// The reserve pile ("the demon"): a face-down packet whose exposed top card
/// is always playable. It is never a drop target — cards only ever leave.
struct CanfieldReserveView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let reserve: [Card]
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let topCard = reserve.last
        let isDragSource: Bool = {
            if case .reserve = selection.dragSource {
                return true
            }
            return false
        }()
        let accessibleTopCard: Card? = topCard.flatMap { card in
            guard card.isFaceUp else { return nil }
            let isDragged = selection.isDragging && selection.isSelected(card)
            return isDragged || hiddenCardIDs.contains(card.id) ? nil : card
        }
        let isAccessibleTopCardSelected = accessibleTopCard.map {
            selection.isSelected($0)
        } ?? false

        VStack(spacing: 4) {
            ZStack {
                PilePlaceholderView(cardSize: cardSize)
                if reserve.count > 1 {
                    CardBackView(cardSize: cardSize)
                }
                if let topCard, topCard.isFaceUp {
                    let isDragged = selection.isDragging && selection.isSelected(topCard)
                    let isHidden = hiddenCardIDs.contains(topCard.id)
                    CardView(
                        card: topCard,
                        isSelected: selection.isSelected(topCard),
                        cardSize: cardSize,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        hintWiggleToken: hintedCardIDs.contains(topCard.id) ? hintWiggleToken : nil,
                        isAccessibilityElement: false
                    )
                    .opacity(isDragged || isHidden ? 0 : 1)
                    .allowsHitTesting(!isHidden)
                    .cardFramePreference(topCard.id)
                    .gesture(dragGesture(.reserve))
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            // The count sits on the felt below the pile — the top card is face
            // up, so a Stock-style overlaid badge would be unreadable on it.
            Text("\(reserve.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .allowsHitTesting(false)
        }
        .onTapGesture {
            session.handleReserveTap()
        }
        .zIndex(isDragSource ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reserve")
        .accessibilityValue(reserveAccessibilityValue(topCard: accessibleTopCard, count: reserve.count))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isAccessibleTopCardSelected ? .isSelected : [])
        .accessibilityHidden(reserve.isEmpty)
    }

    private func reserveAccessibilityValue(topCard: Card?, count: Int) -> String {
        guard count > 0 else { return "Empty" }
        guard let topCard else { return "\(count) cards" }
        return "\(topCard.accessibilityName). \(count) cards"
    }
}

/// See TableauPileView's Equatable note for the exclusion contract.
extension CanfieldReserveView: Equatable {
    nonisolated static func == (lhs: CanfieldReserveView, rhs: CanfieldReserveView) -> Bool {
        lhs.session === rhs.session
            && lhs.reserve == rhs.reserve
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}

/// See TableauPileView's Equatable note for the exclusion contract.
extension CanfieldBoardRowView: Equatable {
    nonisolated static func == (lhs: CanfieldBoardRowView, rhs: CanfieldBoardRowView) -> Bool {
        lhs.session === rhs.session
            && lhs.reserve == rhs.reserve
            && lhs.tableau == rhs.tableau
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.columnSpacing == rhs.columnSpacing
            && lhs.faceDownOffset == rhs.faceDownOffset
            && lhs.faceUpOffset == rhs.faceUpOffset
            && lhs.maxPileHeight == rhs.maxPileHeight
            && lhs.activeTarget == rhs.activeTarget
            && lhs.hintedTarget == rhs.hintedTarget
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}
