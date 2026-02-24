import Foundation

extension GameState {
    static func newFreeCellGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau = Array(repeating: [Card](), count: 8)

        for cardIndex in 0..<52 {
            var card = deck.removeLast()
            card.isFaceUp = true
            tableau[cardIndex % 8].append(card)
        }

        return GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }
}
