import Foundation

extension GameState {
    /// The TriPeaks deal: 28 peak cards (rows of 3/6/9 face down, the 10-card
    /// base face up), one face-up card starting the waste, and the remaining
    /// 23 cards face down in the stock. The hint probe and test fixtures copy
    /// this dealing order verbatim — change them together.
    static func newTriPeaksGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var triPeaks: [Card?] = []

        for index in 0..<TriPeaksGeometry.cardCount {
            var card = deck.removeLast()
            card.isFaceUp = TriPeaksGeometry.row(of: index) == TriPeaksGeometry.rowCount - 1
            triPeaks.append(card)
        }

        var starter = deck.removeLast()
        starter.isFaceUp = true

        return GameState(
            variant: .tripeaks,
            stock: deck,
            waste: [starter],
            wasteDrawCount: 1,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            triPeaks: triPeaks
        )
    }
}
