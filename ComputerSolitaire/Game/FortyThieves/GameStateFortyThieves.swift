import Foundation

nonisolated extension GameState {
    /// The Forty Thieves deal: two full decks shuffled together, ten columns
    /// of four face-up cards dealt column-major (column 0 bottom-to-top first,
    /// then column 1, and so on), and the remaining 64 cards face down in the
    /// stock. The waste starts empty and the eight foundations start empty.
    /// The hint probe and test fixtures copy this dealing order verbatim —
    /// change them together.
    static func newFortyThievesGame() -> GameState {
        var deck = (Card.fullDeck() + Card.fullDeck()).shuffled()
        var tableau: [[Card]] = []

        for _ in 0..<FortyThievesGameRules.columnCount {
            var column: [Card] = []
            for _ in 0..<FortyThievesGameRules.dealColumnDepth {
                var card = deck.removeLast()
                card.isFaceUp = true
                column.append(card)
            }
            tableau.append(column)
        }

        return GameState(
            variant: .fortyThieves,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 8),
            tableau: tableau
        )
    }
}
