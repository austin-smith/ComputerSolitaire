import SwiftUI

/// The stock and waste piles shared by every variant that deals from a stock:
/// Klondike, Spider (stock only), Pyramid, and TriPeaks compose these into
/// their top rows. Variant behavior stays in the session (`handleStockTap`,
/// `handleWasteTap`); these views render value slices and forward interaction.
struct StockView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let stockCount: Int
    let canInteract: Bool
    /// Pyramid's remaining waste recycles; nil for every other variant.
    let recyclesRemaining: Int?
    let cardSize: CGSize
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let hintWiggleToken: UUID

    @AppStorage(SettingsKey.showStockCount) private var isStockCountVisible = true

    var body: some View {
        Button {
            session.handleStockTap()
        } label: {
            ZStack {
                PilePlaceholderView(cardSize: cardSize)
                    .allowsHitTesting(false)
                if stockCount == 0 {
                    if canInteract {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                } else {
                    CardBackView(cardSize: cardSize)
                }
                if isStockCountVisible {
                    Text("\(stockCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .offset(x: cardSize.width * 0.28, y: cardSize.height * 0.38)
                }

                DropHighlightView(
                    cardSize: cardSize,
                    isTargeted: false,
                    isHintTargeted: isHintTargeted,
                    hintOpacity: hintHighlightOpacity
                )
                .allowsHitTesting(false)
            }
            .hintWiggle(token: isHintTargeted ? hintWiggleToken : nil)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: StockFrameKey.self, value: proxy.frame(in: .named("board")))
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canInteract)
        .accessibilityLabel("Stock")
        .accessibilityValue(stockAccessibilityValue)
    }

    private var stockAccessibilityValue: String {
        if stockCount > 0 {
            if let recyclesRemaining {
                return "\(stockCount) cards. \(recyclesRemaining) recycles left"
            }
            return "\(stockCount) cards"
        }
        if canInteract {
            return "Empty. Activate to recycle the waste pile"
        }
        return "Empty"
    }
}

/// Covers every rendered input so unrelated moves prune the stock; the
/// session participates by identity only and the `@AppStorage` count toggle
/// self-invalidates as a DynamicProperty, so it needs no place in `==`.
extension StockView: Equatable {
    nonisolated static func == (lhs: StockView, rhs: StockView) -> Bool {
        lhs.session === rhs.session
            && lhs.stockCount == rhs.stockCount
            && lhs.canInteract == rhs.canInteract
            && lhs.recyclesRemaining == rhs.recyclesRemaining
            && lhs.cardSize == rhs.cardSize
            && lhs.isHintTargeted == rhs.isHintTargeted
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}

struct WasteView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    /// The fanned cards — the session's `visibleWasteCards()`, precomputed
    /// into the top-row snapshot.
    let cards: [Card]
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let fanSpacing: CGFloat
    var isTargeted: Bool = false
    /// Whether tapping the waste does anything. TriPeaks and Golf turn this
    /// off — their waste top is the match target, never a mover — so the pile
    /// neither handles taps nor advertises itself to VoiceOver as a button.
    var isTapEnabled: Bool = true
    let isHintTargeted: Bool
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>
    /// The top card's tilt captured at init for the `Equatable` check: an
    /// invalid waste drag rerolls the hidden top card's tilt while the pile's
    /// contents and selection are unchanged (`beginReturnAnimation`), and
    /// nothing else in `==` would see that write — a pruned waste would then
    /// visibly re-tilt on reveal.
    private let topCardTilt: Double?

    init(
        session: SolitaireViewModel,
        cards: [Card],
        selection: SelectionSnapshot,
        cardSize: CGSize,
        fanSpacing: CGFloat,
        isTargeted: Bool = false,
        isTapEnabled: Bool = true,
        isHintTargeted: Bool,
        isCardTiltEnabled: Bool,
        cardTilts: Binding<[UUID: Double]>,
        hiddenCardIDs: Set<UUID>,
        hintedCardIDs: Set<UUID>,
        hintWiggleToken: UUID,
        drawingCardIDs: Set<UUID>,
        fanProgress: [UUID: Double],
        dragGesture: @escaping (DragOrigin) -> AnyGesture<DragGesture.Value>
    ) {
        self.session = session
        self.cards = cards
        self.selection = selection
        self.cardSize = cardSize
        self.fanSpacing = fanSpacing
        self.isTargeted = isTargeted
        self.isTapEnabled = isTapEnabled
        self.isHintTargeted = isHintTargeted
        self.isCardTiltEnabled = isCardTiltEnabled
        self._cardTilts = cardTilts
        self.hiddenCardIDs = hiddenCardIDs
        self.hintedCardIDs = hintedCardIDs
        self.hintWiggleToken = hintWiggleToken
        self.drawingCardIDs = drawingCardIDs
        self.fanProgress = fanProgress
        self.dragGesture = dragGesture
        self.topCardTilt = cards.last.flatMap { cardTilts.wrappedValue[$0.id] }
    }

    var body: some View {
        let isDragSource: Bool = {
            if case .waste = selection.dragSource {
                return true
            }
            return false
        }()
        let accessibleTopCard: Card? = cards.last.flatMap { card in
            let isDragged = selection.isDragging && selection.isSelected(card)
            let isUnavailable = isDragged || drawingCardIDs.contains(card.id) || hiddenCardIDs.contains(card.id)
            return isUnavailable ? nil : card
        }
        let isAccessibleTopCardSelected = accessibleTopCard.map {
            selection.isSelected($0)
        } ?? false
        let isSelected = cards.contains(where: { selection.isSelected($0) })
        let fanWidth = fanSpacing * CGFloat(max(0, cards.count - 1))

        ZStack(alignment: .topLeading) {
            PilePlaceholderView(cardSize: cardSize)
                .hintWiggle(token: isHintTargeted ? hintWiggleToken : nil)
            DropHighlightView(
                cardSize: cardSize,
                isTargeted: isTargeted,
                isHintTargeted: false,
                hintOpacity: 0
            )
            .zIndex(3)
            .allowsHitTesting(false)
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let isTopCard = index == cards.count - 1
                let isDragged = isTopCard && selection.isDragging && selection.isSelected(card)
                let isDrawing = drawingCardIDs.contains(card.id)
                let isHidden = hiddenCardIDs.contains(card.id)
                let progress = fanProgress[card.id] ?? 1
                let xOffset = CGFloat(index) * fanSpacing * progress
                let cardView = CardView(
                    card: card,
                    isSelected: selection.isSelected(card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil,
                    isAccessibilityElement: false
                )
                .opacity(isDragged || isDrawing || isHidden ? 0 : 1)
                .offset(x: xOffset, y: 0)
                .zIndex(isTopCard ? 2 : Double(index))
                .allowsHitTesting(isTopCard && !isDrawing && !isHidden)
                .cardFramePreference(card.id, xOffset: xOffset)

                if isTopCard {
                    cardView.gesture(dragGesture(.waste))
                } else {
                    cardView
                }
            }
        }
        .frame(width: cardSize.width + fanWidth, height: cardSize.height, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: WasteFrameKey.self, value: proxy.frame(in: .named("board")))
            }
        )
        .onTapGesture {
            guard isTapEnabled else { return }
            session.handleWasteTap()
        }
        .zIndex(isDragSource || isSelected ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waste")
        .accessibilityValue(accessibleTopCard?.accessibilityName ?? "Empty")
        .accessibilityAddTraits(isTapEnabled ? .isButton : [])
        .accessibilityAddTraits(isAccessibleTopCardSelected ? .isSelected : [])
        // Declared explicitly because the installed tap gesture would otherwise
        // let assistive technologies infer interactivity even when disabled.
        .accessibilityRespondsToUserInteraction(isTapEnabled)
        .accessibilityHidden(accessibleTopCard == nil)
    }
}

/// Covers every rendered input — including the fan-driving `drawingCardIDs`
/// and `fanProgress`, and the captured `topCardTilt` — so unrelated moves
/// prune the waste. The session participates by identity only; the tilt
/// binding and gesture closure are excluded per CardView's contract.
extension WasteView: Equatable {
    nonisolated static func == (lhs: WasteView, rhs: WasteView) -> Bool {
        lhs.session === rhs.session
            && lhs.cards == rhs.cards
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.fanSpacing == rhs.fanSpacing
            && lhs.isTargeted == rhs.isTargeted
            && lhs.isTapEnabled == rhs.isTapEnabled
            && lhs.isHintTargeted == rhs.isHintTargeted
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
            && lhs.drawingCardIDs == rhs.drawingCardIDs
            && lhs.fanProgress == rhs.fanProgress
            && lhs.topCardTilt == rhs.topCardTilt
    }
}
