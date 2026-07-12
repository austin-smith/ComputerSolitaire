import SwiftUI
import Observation

struct SpiderStockView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let hintWiggleToken: UUID

    var body: some View {
        Button {
            viewModel.handleStockTap()
        } label: {
            ZStack {
                PilePlaceholderView(cardSize: cardSize)
                    .allowsHitTesting(false)
                if !viewModel.state.stock.isEmpty {
                    CardBackView(cardSize: cardSize)
                    Text("\(viewModel.state.stock.count)")
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
        .disabled(viewModel.state.stock.isEmpty)
        .accessibilityLabel("Stock")
        .accessibilityValue(stockAccessibilityValue)
    }

    private var stockAccessibilityValue: String {
        guard !viewModel.state.stock.isEmpty else { return "Empty" }
        return "\(viewModel.state.stock.count) cards. Deals one card to each pile"
    }
}
