import Foundation

nonisolated extension GameState {
    /// The Golf deal: seven columns of five face-up cards dealt column-major
    /// (column 0 bottom-to-top first, then column 1, and so on), one face-up
    /// card starting the waste, and the remaining 16 cards face down in the
    /// stock. The hint probe and test fixtures copy this dealing order
    /// verbatim — change them together.
    static func newGolfGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau: [[Card]] = []

        for _ in 0..<GolfGameRules.columnCount {
            var column: [Card] = []
            for _ in 0..<GolfGameRules.columnDepth {
                var card = deck.removeLast()
                card.isFaceUp = true
                column.append(card)
            }
            tableau.append(column)
        }

        var starter = deck.removeLast()
        starter.isFaceUp = true

        return GameState(
            variant: .golf,
            stock: deck,
            waste: [starter],
            wasteDrawCount: 1,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }
}
