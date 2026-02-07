import Foundation
import Observation

@Observable
final class SolitaireViewModel {
    static let maxUndoHistoryCount = 200

    private(set) var state: GameState
    var selection: Selection?
    var isDragging: Bool = false
    private(set) var movesCount: Int = 0
    private(set) var stockDrawCount: Int = 3

    private var history: [GameSnapshot] = []

    init() {
        state = GameState.newGame()
    }

    var isWin: Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
    }

    var canUndo: Bool {
        !history.isEmpty
    }

    func newGame(drawMode: DrawMode = .three) {
        state = GameState.newGame()
        selection = nil
        isDragging = false
        movesCount = 0
        stockDrawCount = drawMode.rawValue
        state.wasteDrawCount = 0
        history.removeAll()
    }

    func updateDrawMode(_ drawMode: DrawMode) {
        stockDrawCount = drawMode.rawValue
        if drawMode == .one {
            state.wasteDrawCount = min(1, state.waste.count)
        } else {
            state.wasteDrawCount = min(state.wasteDrawCount, drawMode.rawValue)
        }
        selection = nil
        isDragging = false
    }

    func visibleWasteCards() -> [Card] {
        let count = min(state.wasteDrawCount, stockDrawCount)
        return Array(state.waste.suffix(count))
    }

    func undo() {
        guard let snapshot = history.popLast() else { return }
        state = snapshot.state
        movesCount = snapshot.movesCount
        selection = nil
        isDragging = false
    }

    func peekUndoSnapshot() -> GameSnapshot? {
        history.last
    }

    func persistencePayload() -> SavedGamePayload {
        SavedGamePayload(
            state: state,
            movesCount: movesCount,
            stockDrawCount: stockDrawCount,
            history: history
        )
    }

    @discardableResult
    func restore(from payload: SavedGamePayload) -> Bool {
        guard let sanitizedPayload = payload.sanitizedForRestore() else { return false }
        state = sanitizedPayload.state
        movesCount = sanitizedPayload.movesCount
        stockDrawCount = sanitizedPayload.stockDrawCount
        history = Array(sanitizedPayload.history.suffix(Self.maxUndoHistoryCount))
        selection = nil
        isDragging = false
        return true
    }

    func handleStockTap() {
        selection = nil
        isDragging = false
        if state.stock.isEmpty {
            recycleWaste()
        } else {
            drawFromStock()
        }
    }

    func handleWasteTap() {
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return }
        if selection?.source == .waste {
            selection = nil
            return
        }
        isDragging = false
        selection = Selection(source: .waste, cards: [top])
    }

    func handleFoundationTap(index: Int) {
        if selection != nil {
            if tryMoveSelection(to: .foundation(index)) {
                return
            }
        }
        isDragging = false
        selectFromFoundation(index: index)
    }

    func handleTableauTap(pileIndex: Int, cardIndex: Int?) {
        if let cardIndex {
            let pile = state.tableau[pileIndex]
            guard cardIndex < pile.count else { return }
            let card = pile[cardIndex]

            if !card.isFaceUp {
                if cardIndex == pile.count - 1 {
                    pushHistory(
                        undoContext: UndoAnimationContext(
                            action: .flipTableauTop,
                            cardIDs: [card.id]
                        )
                    )
                    state.tableau[pileIndex][cardIndex].isFaceUp = true
                    movesCount += 1
                }
                selection = nil
                return
            }

            if let selection {
                if selection.source == .tableau(pile: pileIndex, index: cardIndex) {
                    self.selection = nil
                    return
                }
                if tryMoveSelection(to: .tableau(pileIndex)) {
                    return
                }
            }

            isDragging = false
            selectFromTableau(pileIndex: pileIndex, cardIndex: cardIndex)
        } else {
            if selection != nil {
                _ = tryMoveSelection(to: .tableau(pileIndex))
            }
        }
    }

    func isSelected(card: Card) -> Bool {
        selection?.cards.contains(where: { $0.id == card.id }) == true
    }

    @discardableResult
    func startDragFromWaste() -> Bool {
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return false }
        selection = Selection(source: .waste, cards: [top])
        isDragging = true
        return true
    }

    @discardableResult
    func startDragFromFoundation(index: Int) -> Bool {
        guard let top = state.foundations[index].last else { return false }
        selection = Selection(source: .foundation(pile: index), cards: [top])
        isDragging = true
        return true
    }

    @discardableResult
    func startDragFromTableau(pileIndex: Int, cardIndex: Int) -> Bool {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return false }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return false }
        let cards = Array(pile[cardIndex...])
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
            return GameRules.canMoveToTableau(
                card: movingCard,
                destinationPile: state.tableau[index]
            )
        }
    }

    @discardableResult
    func handleDrop(to destination: Destination) -> Bool {
        let moved = tryMoveSelection(to: destination)
        if !moved {
            selection = nil
        }
        isDragging = false
        return moved
    }

    func cancelDrag() {
        selection = nil
        isDragging = false
    }
}

private extension SolitaireViewModel {
    func drawFromStock() {
        guard !state.stock.isEmpty else { return }
        let drawCount = min(stockDrawCount, state.stock.count)
        let drawnCardIDs = (0..<drawCount).map { offset in
            state.stock[state.stock.count - 1 - offset].id
        }
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .drawFromStock,
                cardIDs: drawnCardIDs
            )
        )
        for _ in 0..<drawCount {
            var card = state.stock.removeLast()
            card.isFaceUp = true
            state.waste.append(card)
        }
        state.wasteDrawCount = drawCount
        movesCount += 1
    }

    func recycleWaste() {
        guard state.stock.isEmpty, !state.waste.isEmpty else { return }
        let visibleWasteIDs = visibleWasteCards().map(\.id)
        let animatedWasteIDs = visibleWasteIDs.isEmpty
            ? [state.waste.last?.id].compactMap { $0 }
            : visibleWasteIDs
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .recycleWaste,
                cardIDs: animatedWasteIDs
            )
        )
        var newStock: [Card] = []
        for card in state.waste.reversed() {
            var newCard = card
            newCard.isFaceUp = false
            newStock.append(newCard)
        }
        state.stock = newStock
        state.waste.removeAll()
        state.wasteDrawCount = 0
        movesCount += 1
    }

    func selectFromTableau(pileIndex: Int, cardIndex: Int) {
        let pile = state.tableau[pileIndex]
        guard cardIndex < pile.count else { return }
        let card = pile[cardIndex]
        guard card.isFaceUp else { return }
        let cards = Array(pile[cardIndex...])
        selection = Selection(source: .tableau(pile: pileIndex, index: cardIndex), cards: cards)
    }

    func selectFromFoundation(index: Int) {
        guard let top = state.foundations[index].last else { return }
        selection = Selection(source: .foundation(pile: index), cards: [top])
    }

    func tryMoveSelection(to destination: Destination) -> Bool {
        guard let selection, let movingCard = selection.cards.first else { return false }

        switch destination {
        case .foundation(let index):
            guard selection.cards.count == 1 else { return false }
            guard GameRules.canMoveToFoundation(card: movingCard, foundation: state.foundations[index]) else { return false }
            pushHistory(
                undoContext: UndoAnimationContext(
                    action: .moveSelection,
                    cardIDs: selection.cards.map(\.id)
                )
            )
            removeSelection(selection)
            state.foundations[index].append(movingCard)
            movesCount += 1
            self.selection = nil
            return true

        case .tableau(let index):
            guard GameRules.canMoveToTableau(card: movingCard, destinationPile: state.tableau[index]) else { return false }
            pushHistory(
                undoContext: UndoAnimationContext(
                    action: .moveSelection,
                    cardIDs: selection.cards.map(\.id)
                )
            )
            removeSelection(selection)
            state.tableau[index].append(contentsOf: selection.cards)
            movesCount += 1
            self.selection = nil
            return true
        }
    }

    func removeSelection(_ selection: Selection) {
        switch selection.source {
        case .waste:
            _ = state.waste.popLast()
            if stockDrawCount == DrawMode.one.rawValue {
                state.wasteDrawCount = min(1, state.waste.count)
            } else {
                state.wasteDrawCount = max(0, state.wasteDrawCount - 1)
            }
        case .foundation(let pile):
            _ = state.foundations[pile].popLast()
        case .tableau(let pile, let index):
            var cards = state.tableau[pile]
            cards.removeSubrange(index..<cards.count)
            state.tableau[pile] = cards
            flipTopCardIfNeeded(in: pile)
        }
    }

    func flipTopCardIfNeeded(in pileIndex: Int) {
        guard let lastIndex = state.tableau[pileIndex].indices.last else { return }
        if !state.tableau[pileIndex][lastIndex].isFaceUp {
            state.tableau[pileIndex][lastIndex].isFaceUp = true
        }
    }

    func pushHistory(undoContext: UndoAnimationContext? = nil) {
        history.append(
            GameSnapshot(
                state: state,
                movesCount: movesCount,
                undoContext: undoContext
            )
        )
        if history.count > Self.maxUndoHistoryCount {
            history.removeFirst()
        }
    }
}
