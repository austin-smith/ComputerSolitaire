import Foundation

extension GameState {
    /// The Canfield deal: thirteen cards face down into the reserve with its
    /// top card turned face up, one face-up base card onto the first
    /// foundation (its rank is where all four foundations start), one face-up
    /// card onto each of the four tableau piles, and the remaining 34 cards
    /// face down in the stock. The waste starts empty.
    /// The hint probe and test fixtures copy this dealing order verbatim —
    /// change them together.
    static func newCanfieldGame() -> GameState {
        var deck = Card.fullDeck().shuffled()

        var reserve: [Card] = []
        for _ in 0..<CanfieldGameRules.reserveCardCount {
            reserve.append(deck.removeLast())
        }
        reserve[reserve.count - 1].isFaceUp = true

        var baseCard = deck.removeLast()
        baseCard.isFaceUp = true
        var foundations: [[Card]] = Array(repeating: [], count: 4)
        foundations[0] = [baseCard]

        var tableau: [[Card]] = []
        for _ in 0..<CanfieldGameRules.tableauPileCount {
            var card = deck.removeLast()
            card.isFaceUp = true
            tableau.append([card])
        }

        return GameState(
            variant: .canfield,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            freeCells: Array(repeating: nil, count: 4),
            foundations: foundations,
            tableau: tableau,
            reserve: reserve
        )
    }
}
