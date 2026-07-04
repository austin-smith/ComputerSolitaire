import SwiftUI
import Observation

struct StockView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let hintWiggleToken: UUID

    var body: some View {
        ZStack {
            PilePlaceholderView(cardSize: cardSize)
                .allowsHitTesting(false)
            if viewModel.state.stock.isEmpty {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                CardBackView(cardSize: cardSize)
            }
            Text("\(viewModel.state.stock.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .offset(x: cardSize.width * 0.28, y: cardSize.height * 0.38)

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
        .onTapGesture {
            viewModel.handleStockTap()
        }
        .accessibilityLabel("Stock")
    }
}

struct WasteView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let fanSpacing: CGFloat
    let isHintTargeted: Bool
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let isDragSource: Bool = {
            guard viewModel.isDragging, let selection = viewModel.selection else { return false }
            if case .waste = selection.source {
                return true
            }
            return false
        }()
        let visibleWaste = viewModel.visibleWasteCards()
        let isSelected = visibleWaste.contains(where: { viewModel.isSelected(card: $0) })
        let fanWidth = fanSpacing * CGFloat(max(0, visibleWaste.count - 1))

        ZStack(alignment: .topLeading) {
            PilePlaceholderView(cardSize: cardSize)
                .hintWiggle(token: isHintTargeted ? hintWiggleToken : nil)
            ForEach(Array(visibleWaste.enumerated()), id: \.element.id) { index, card in
                let isTopCard = index == visibleWaste.count - 1
                let isDragged = isTopCard && viewModel.isDragging && viewModel.isSelected(card: card)
                let isDrawing = drawingCardIDs.contains(card.id)
                let isHidden = hiddenCardIDs.contains(card.id)
                let progress = fanProgress[card.id] ?? 1
                let xOffset = CGFloat(index) * fanSpacing * progress
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil
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
            viewModel.handleWasteTap()
        }
        .zIndex(isDragSource || isSelected ? 10 : 0)
        .accessibilityLabel("Waste")
    }
}
