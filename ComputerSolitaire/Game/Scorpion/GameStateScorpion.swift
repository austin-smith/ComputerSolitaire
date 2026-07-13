import Foundation

extension GameState {
    static func newScorpionGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau = Array(repeating: [Card](), count: 7)

        for pileIndex in 0..<7 {
            let faceDownCount = pileIndex < 4 ? 3 : 0
            for cardIndex in 0..<7 {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex >= faceDownCount
                tableau[pileIndex].append(card)
            }
        }

        return GameState(
            variant: .scorpion,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }
}
