import Foundation

extension SolitaireViewModel {
    func canSelectFreeCellTableauCards(_ cards: [Card]) -> Bool {
        GameRules.isValidDescendingAlternatingSequence(cards)
    }

    func handleFreeCellTap(index: Int) {
        guard state.variant == .freecell else { return }
        guard state.freeCells.indices.contains(index) else { return }
        if selection != nil || state.freeCells[index] != nil {
            HapticManager.shared.play(.cardPickUp)
        }
        if selection != nil {
            if tryMoveSelection(to: .freeCell(index)) {
                return
            }
        } else if let card = state.freeCells[index] {
            let tappedSelection = Selection(source: .freeCell(slot: index), cards: [card])
            if queueBestAutoMove(
                for: tappedSelection,
                playFailureFeedback: false
            ) {
                return
            }
        }
        isDragging = false
        selectFromFreeCell(index: index)
    }

    @discardableResult
    func startDragFromFreeCell(index: Int) -> Bool {
        startDrag(from: .freeCell(index))
    }

    func freeCellCanMoveStack(_ cards: [Card], to destination: Destination) -> Bool {
        guard cards.count > 1 else { return true }
        guard GameRules.isValidDescendingAlternatingSequence(cards) else { return false }
        let maxTransferCount = GameRules.maxFreeCellTransferCount(
            freeCellSlots: state.freeCells,
            tableau: state.tableau,
            destination: destination
        )
        return cards.count <= maxTransferCount
    }
}
