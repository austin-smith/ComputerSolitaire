import SwiftUI
import Observation

struct ScorpionTopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
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
            // Stock on the left like Spider's, two clear columns, then the
            // four banked-run piles aligned over tableau columns 4-7.
            TableauStockView(
                viewModel: viewModel,
                cardSize: cardSize,
                isHintTargeted: isStockHinted,
                hintHighlightOpacity: hintHighlightOpacity,
                hintWiggleToken: hintWiggleToken,
                dealDescription: "Deals one card onto each of the first three piles"
            )
            .frame(width: cardSize.width, alignment: .leading)

            ForEach(0..<2) { _ in
                Color.clear
                    .frame(width: cardSize.width, height: cardSize.height)
                    .accessibilityHidden(true)
            }

            // Iterate the piles the state actually holds, not a fixed 0..<4:
            // during a game switch this row can re-evaluate against the
            // incoming variant's eight-foundation state before the board
            // replaces it.
            ForEach(Array(viewModel.state.foundations.enumerated()), id: \.offset) { index, pile in
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
