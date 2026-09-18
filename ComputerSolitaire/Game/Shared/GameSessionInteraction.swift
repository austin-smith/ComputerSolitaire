import Foundation

extension SolitaireViewModel {
    @discardableResult
    func startDrag(from origin: DragOrigin) -> Bool {
        guard let selection = dragSelection(from: origin) else { return false }
        clearHint()
        self.selection = selection
        isDragging = true
        return true
    }

    /// Resolve a legal pickup without changing selection or hiding its cards.
    /// SwiftUI requests transfer data before it starts the physical drag.
    func dragSelection(from origin: DragOrigin) -> Selection? {
        switch origin {
        case .waste:
            guard state.variant.dealsFromStock,
                  state.variant != .tripeaks, state.variant != .golf,
                  let top = state.waste.last, state.wasteDrawCount > 0 else { return nil }
            return Selection(source: .waste, cards: [top])
        case .foundation(let index):
            guard state.variant.allowsFoundationRollback,
                  state.foundations.indices.contains(index),
                  let top = state.foundations[index].last else { return nil }
            return Selection(source: .foundation(pile: index), cards: [top])
        case .freeCell(let index):
            guard state.variant == .freecell,
                  state.freeCells.indices.contains(index),
                  let card = state.freeCells[index] else { return nil }
            return Selection(source: .freeCell(slot: index), cards: [card])
        case .tableau(let pileIndex, let cardIndex):
            guard state.tableau.indices.contains(pileIndex) else { return nil }
            let pile = state.tableau[pileIndex]
            guard pile.indices.contains(cardIndex), pile[cardIndex].isFaceUp else { return nil }
            let cards = Array(pile[cardIndex...])
            if state.variant == .freecell,
               !freeCellCanMoveStack(cards, to: .tableau(pileIndex)) { return nil }
            if state.variant == .spider, !canSelectTableauCards(cards) { return nil }
            if state.variant == .golf || state.variant == .fortyThieves,
               cardIndex != pile.count - 1 { return nil }
            if state.variant == .canfield, cardIndex != 0, cardIndex != pile.count - 1 { return nil }
            return Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
        case .pyramid(let index):
            guard state.pyramid.indices.contains(index),
                  let card = state.pyramid[index],
                  PyramidGameRules.isSelectable(index: index, in: state.pyramid) else { return nil }
            return Selection(source: .pyramid(index: index), cards: [card])
        case .triPeaks(let index):
            guard state.triPeaks.indices.contains(index),
                  let card = state.triPeaks[index], card.isFaceUp,
                  TriPeaksGeometry.isUncovered(index, in: state.triPeaks) else { return nil }
            return Selection(source: .triPeaks(index: index), cards: [card])
        case .reserve:
            guard state.variant == .canfield,
                  let top = state.reserve.last, top.isFaceUp else { return nil }
            return Selection(source: .reserve, cards: [top])
        }
    }

    @discardableResult
    func startDragFromTableau(pileIndex: Int, cardIndex: Int) -> Bool {
        startDrag(from: .tableau(pile: pileIndex, index: cardIndex))
    }

    func canDrop(to destination: Destination) -> Bool {
        guard let selection else { return false }
        return canDrop(selection, to: destination)
    }

    func canDrop(_ selection: Selection, to destination: Destination) -> Bool {
        guard let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard state.foundations.indices.contains(index) else { return false }
            guard state.variant.playerBuildsFoundations else { return false }
            guard selection.cards.count == 1 else { return false }
            return GameRules.canMoveToFoundation(
                card: movingCard,
                foundation: state.foundations[index],
                in: state
            )
        case .tableau(let index):
            guard state.tableau.indices.contains(index) else { return false }
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
            if state.variant == .canfield {
                // The card rule alone cannot see sources: spaces take only the
                // waste top (once the reserve is out) and piles move whole.
                return CanfieldGameRules.allowsTableauTransfer(
                    selection: selection,
                    destinationPile: state.tableau[index],
                    in: state
                )
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
            case .foundation, .freeCell, .tableau, .triPeaks, .reserve:
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
            case .klondike, .freecell, .yukon, .spider, .fortyThieves, .scorpion, .canfield:
                return false
            }

        case .discard:
            guard state.variant == .pyramid else { return false }
            return PyramidGameRules.canRemoveKing(selection: selection, in: state)
        }
    }
}
