import Foundation

extension SolitaireViewModel {
    @discardableResult
    func startDragFromTableau(pileIndex: Int, cardIndex: Int) -> Bool {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return false }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return false }
        clearHint()
        let cards = Array(pile[cardIndex...])
        if state.variant == .freecell,
           !freeCellCanMoveStack(cards, to: .tableau(pileIndex)) {
            return false
        }
        selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
        isDragging = true
        return true
    }

    func canDrop(to destination: Destination) -> Bool {
        guard let selection, let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1 else { return false }
            return GameRules.canMoveToFoundation(
                card: movingCard,
                foundation: state.foundations[index]
            )
        case .tableau(let index):
            guard GameRules.canMoveToTableau(
                card: movingCard,
                destinationPile: state.tableau[index],
                variant: state.variant
            ) else { return false }
            if state.variant == .freecell {
                return freeCellCanMoveStack(selection.cards, to: destination)
            }
            return true
        case .freeCell(let index):
            guard state.variant == .freecell else { return false }
            guard state.freeCells.indices.contains(index) else { return false }
            guard selection.cards.count == 1 else { return false }
            return GameRules.canMoveToFreeCell(destination: state.freeCells[index])
        }
    }
}
