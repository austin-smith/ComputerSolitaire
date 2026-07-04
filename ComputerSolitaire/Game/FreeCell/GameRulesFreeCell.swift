enum FreeCellGameRules {
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        if destinationPile.isEmpty {
            return true
        }
        guard let top = destinationPile.last else { return false }
        return top.isFaceUp
            && top.suit.isRed != card.suit.isRed
            && card.rank.rawValue == top.rank.rawValue - 1
    }

    static func canMoveToFreeCell(destination: Card?) -> Bool {
        destination == nil
    }

    static func maxTransferCount(
        freeCellSlots: [Card?],
        tableau: [[Card]],
        destination: Destination
    ) -> Int {
        let emptyFreeCells = freeCellSlots.filter { $0 == nil }.count
        var emptyTableau = tableau.count(where: \.isEmpty)
        if case .tableau(let destinationIndex) = destination,
           tableau.indices.contains(destinationIndex),
           tableau[destinationIndex].isEmpty {
            emptyTableau = max(0, emptyTableau - 1)
        }
        return (emptyFreeCells + 1) * (1 << emptyTableau)
    }
}
