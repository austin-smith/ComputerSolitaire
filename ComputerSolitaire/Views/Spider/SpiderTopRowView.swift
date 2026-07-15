import SwiftUI

struct SpiderTopRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let board: TopRowSnapshot
    let selection: SelectionSnapshot
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let isStockHinted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintWiggleToken: UUID

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            // Stock on the left like Klondike's, one clear column, then the
            // eight banked-run piles aligned over tableau columns 3-10.
            TableauStockView(
                session: session,
                stockCount: board.stockCount,
                cardSize: cardSize,
                isHintTargeted: isStockHinted,
                hintHighlightOpacity: hintHighlightOpacity,
                hintWiggleToken: hintWiggleToken,
                dealDescription: "Deals one card to each pile"
            )
            .frame(width: cardSize.width, alignment: .leading)

            Color.clear
                .frame(width: cardSize.width, height: cardSize.height)
                .accessibilityHidden(true)

            // Iterate the piles the state actually holds, not a fixed 0..<8:
            // during a game switch this row can re-evaluate against the
            // incoming variant's four-foundation state before the board
            // replaces it.
            ForEach(Array(board.foundations.enumerated()), id: \.offset) { index, pile in
                CompletedRunPileView(
                    pile: pile,
                    index: index,
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs
                )
                .frame(width: cardSize.width, alignment: .leading)
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}
