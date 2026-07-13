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
        if state.variant == .spider, !canSelectTableauCards(cards) {
            return false
        }
        if state.variant == .golf || state.variant == .fortyThieves,
           cardIndex != pile.count - 1 {
            // Only the exposed card of a Golf or Forty Thieves column can
            // move; without this guard a buried-card drag would build a
            // multi-card selection whose legality checks only see its first card.
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
            guard state.variant.playerBuildsFoundations else { return false }
            guard selection.cards.count == 1 else { return false }
            return GameRules.canMoveToFoundation(
                card: movingCard,
                foundation: state.foundations[index]
            )
        case .tableau(let index):
            // Dropping a stack back onto its own pile is a cancel, not a move. The
            // destination pile still contains the lifted cards here, so in Yukon an
            // unordered group could otherwise "land" on itself and flip the exposed
            // face-down card without any real move being made.
            if case .tableau(let sourcePile, _) = selection.source, sourcePile == index {
                return false
            }
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

        case .pyramid(let index):
            guard state.variant == .pyramid else { return false }
            switch selection.source {
            case .pyramid(let sourceIndex):
                return PyramidGameRules.canRemovePair(sourceIndex, index, in: state.pyramid)
            case .waste:
                return PyramidGameRules.canRemovePairWithWasteTop(pyramidIndex: index, in: state)
            case .foundation, .freeCell, .tableau, .triPeaks:
                return false
            }

        case .waste:
            switch state.variant {
            case .pyramid:
                guard case .pyramid(let sourceIndex) = selection.source else { return false }
                return PyramidGameRules.canRemovePairWithWasteTop(
                    pyramidIndex: sourceIndex,
                    in: state
                )
            case .tripeaks:
                guard case .triPeaks(let sourceIndex) = selection.source else { return false }
                return TriPeaksGameRules.canPlay(index: sourceIndex, in: state)
            case .golf:
                guard case .tableau(let pile, let index) = selection.source,
                      state.tableau.indices.contains(pile),
                      index == state.tableau[pile].count - 1 else { return false }
                return GolfGameRules.canPlay(column: pile, in: state)
            case .klondike, .freecell, .yukon, .spider, .fortyThieves:
                return false
            }

        case .discard:
            guard state.variant == .pyramid else { return false }
            return PyramidGameRules.canRemoveKing(selection: selection, in: state)
        }
    }
}
