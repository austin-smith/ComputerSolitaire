import SwiftUI

/// The stock for the variants that deal it directly onto the tableau (Spider,
/// Scorpion): a tap deals, there is no waste, and an empty stock is inert.
struct TableauStockView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let stockCount: Int
    let cardSize: CGSize
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let hintWiggleToken: UUID
    /// How a deal lands, for accessibility — e.g. "Deals one card to each pile".
    let dealDescription: String

    @AppStorage(SettingsKey.showStockCount) private var isStockCountVisible = true

    var body: some View {
        Button {
            session.handleStockTap()
        } label: {
            ZStack {
                PilePlaceholderView(cardSize: cardSize)
                    .allowsHitTesting(false)
                if stockCount > 0 {
                    CardBackView(cardSize: cardSize)
                    if isStockCountVisible {
                        Text("\(stockCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .offset(x: cardSize.width * 0.28, y: cardSize.height * 0.38)
                    }
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
        .disabled(stockCount == 0)
        .accessibilityLabel("Stock")
        .accessibilityValue(stockAccessibilityValue)
    }

    private var stockAccessibilityValue: String {
        guard stockCount > 0 else { return "Empty" }
        return "\(stockCount) cards. \(dealDescription)"
    }
}

/// See StockView's Equatable note; the `@AppStorage` toggle self-invalidates.
extension TableauStockView: Equatable {
    nonisolated static func == (lhs: TableauStockView, rhs: TableauStockView) -> Bool {
        lhs.session === rhs.session
            && lhs.stockCount == rhs.stockCount
            && lhs.cardSize == rhs.cardSize
            && lhs.isHintTargeted == rhs.isHintTargeted
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.hintWiggleToken == rhs.hintWiggleToken
            && lhs.dealDescription == rhs.dealDescription
    }
}
