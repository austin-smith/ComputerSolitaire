import Foundation

extension GameState {
    static func newKlondikeGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau = Array(repeating: [Card](), count: 7)

        for pileIndex in 0..<7 {
            for cardIndex in 0...pileIndex {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex == pileIndex
                tableau[pileIndex].append(card)
            }
        }

        return GameState(
            variant: .klondike,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }
}
