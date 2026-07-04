import Foundation

extension SolitaireViewModel {
    func configureFreeCellNewGame() {
        setStockDrawCount(DrawMode.three.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(0)
    }

    func configureFreeCellRedeal() {
        setScoringDrawCount(stockDrawCount)
        setWasteDrawCount(0)
    }

    func sanitizeFreeCellRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = 0
        return sanitizedState
    }

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
        guard state.variant == .freecell else { return false }
        guard state.freeCells.indices.contains(index), let card = state.freeCells[index] else { return false }
        clearHint()
        selection = Selection(source: .freeCell(slot: index), cards: [card])
        isDragging = true
        return true
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
