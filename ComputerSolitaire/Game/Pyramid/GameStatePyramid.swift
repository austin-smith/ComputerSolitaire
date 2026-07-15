import Foundation

nonisolated extension GameState {
    static func newPyramidGame() -> GameState {
        var deck = Card.fullDeck().shuffled()
        var pyramid: [Card?] = []

        for _ in 0..<PyramidGeometry.cardCount {
            var card = deck.removeLast()
            card.isFaceUp = true
            pyramid.append(card)
        }

        return GameState(
            variant: .pyramid,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            pyramid: pyramid,
            discard: []
        )
    }
}
