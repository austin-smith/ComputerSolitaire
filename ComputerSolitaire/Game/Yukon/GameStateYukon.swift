import Foundation

nonisolated extension GameState {
    static func newYukonGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var tableau = Array(repeating: [Card](), count: 7)

        for pileIndex in 0..<7 {
            let faceDownCount = pileIndex == 0 ? 0 : pileIndex
            let faceUpCount = pileIndex == 0 ? 1 : 5
            for cardIndex in 0..<(faceDownCount + faceUpCount) {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex >= faceDownCount
                tableau[pileIndex].append(card)
            }
        }

        return GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )
    }
}
