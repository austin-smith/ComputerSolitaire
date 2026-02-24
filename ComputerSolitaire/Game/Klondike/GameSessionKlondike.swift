import Foundation

extension SolitaireViewModel {
    func configureKlondikeNewGame(drawMode: DrawMode) {
        setStockDrawCount(drawMode.rawValue)
        setScoringDrawCount(drawMode.rawValue)
        setWasteDrawCount(0)
    }

    func configureKlondikeRedeal() {
        setScoringDrawCount(stockDrawCount)
        let clampedWasteDrawCount = min(max(0, state.wasteDrawCount), min(stockDrawCount, state.waste.count))
        setWasteDrawCount(clampedWasteDrawCount)
    }

    func sanitizeKlondikeRedealState(_ baseState: GameState, stockDrawCount: Int) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = min(
            max(0, sanitizedState.wasteDrawCount),
            min(stockDrawCount, sanitizedState.waste.count)
        )
        return sanitizedState
    }

    @discardableResult
    func handleKlondikeTableauFaceDownTap(
        pile: [Card],
        pileIndex: Int,
        cardIndex: Int,
        card: Card
    ) -> Bool {
        guard !card.isFaceUp else { return false }
        guard cardIndex == pile.count - 1 else {
            selection = nil
            return true
        }
        clearHint()
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .flipTableauTop,
                cardIDs: [card.id]
            )
        )
        state.tableau[pileIndex][cardIndex].isFaceUp = true
        incrementMovesCount()
        applyScore(.turnOverTableauCard)
        SoundManager.shared.play(.cardFlipFaceUp)
        HapticManager.shared.play(.cardFlipFaceUp)
        refreshAutoFinishAvailability()
        selection = nil
        return true
    }

    var supportsDrawMode: Bool {
        state.variant == .klondike
    }

    func updateDrawMode(_ drawMode: DrawMode) {
        guard state.variant == .klondike else { return }
        clearHint()
        setStockDrawCount(drawMode.rawValue)
        if drawMode == .one {
            setWasteDrawCount(min(1, state.waste.count))
        } else {
            setWasteDrawCount(min(state.wasteDrawCount, drawMode.rawValue))
        }
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        refreshAutoFinishAvailability()
    }

    func visibleWasteCards() -> [Card] {
        guard state.variant == .klondike else { return [] }
        let count = min(state.wasteDrawCount, stockDrawCount)
        return Array(state.waste.suffix(count))
    }

    func handleStockTap() {
        guard state.variant == .klondike else { return }
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        if state.stock.isEmpty {
            recycleWaste()
        } else {
            drawFromStock()
        }
    }

    func handleWasteTap() {
        guard state.variant == .klondike else { return }
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return }
        HapticManager.shared.play(.cardPickUp)
        let wasteSelection = Selection(source: .waste, cards: [top])
        if queueBestAutoMove(for: wasteSelection) {
            return
        }
        if selection?.source == .waste {
            selection = nil
            return
        }
        isDragging = false
        selection = wasteSelection
    }

    @discardableResult
    func startDragFromWaste() -> Bool {
        guard state.variant == .klondike else { return false }
        guard let top = state.waste.last, state.wasteDrawCount > 0 else { return false }
        clearHint()
        selection = Selection(source: .waste, cards: [top])
        isDragging = true
        return true
    }

    @discardableResult
    func queueNextAutoFinishMove() -> Bool {
        isDragging = false
        guard state.variant == .klondike else { return false }
        guard let move = AutoFinishPlanner.nextAutoFinishMove(in: state) else {
            return false
        }

        pendingAutoMove = PendingAutoMove(
            id: UUID(),
            selection: move.selection,
            destination: move.destination
        )
        return true
    }

    func drawFromStock() {
        guard !state.stock.isEmpty else { return }
        clearHint()
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
        setWasteDrawCount(drawCount)
        incrementMovesCount()
        SoundManager.shared.play(.cardDrawFromStock)
        HapticManager.shared.play(.stockDraw)
        refreshAutoFinishAvailability()
    }

    func recycleWaste() {
        guard state.stock.isEmpty, !state.waste.isEmpty else { return }
        clearHint()
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
        let recycledStock = state.waste.reversed().map { card in
            var newCard = card
            newCard.isFaceUp = false
            return newCard
        }
        state.stock = recycledStock
        state.waste.removeAll()
        setWasteDrawCount(0)
        incrementMovesCount()
        if stockDrawCount == DrawMode.one.rawValue {
            applyScore(.recycleWasteInDrawOne)
        }
        SoundManager.shared.play(.wasteRecycleToStock)
        HapticManager.shared.play(.wasteRecycle)
        refreshAutoFinishAvailability()
    }

    func flipKlondikeTopCardIfNeeded(in pileIndex: Int) {
        guard let lastIndex = state.tableau[pileIndex].indices.last else { return }
        guard !state.tableau[pileIndex][lastIndex].isFaceUp else { return }
        state.tableau[pileIndex][lastIndex].isFaceUp = true
        applyScore(.turnOverTableauCard)
        SoundManager.shared.play(.cardFlipFaceUp)
        HapticManager.shared.play(.cardFlipFaceUp)
    }

    func applyKlondikeMoveScore(for source: Selection.Source, destination: Destination) {
        switch (source, destination) {
        case (.waste, .tableau):
            applyScore(.wasteToTableau)
        case (.waste, .foundation):
            applyScore(.wasteToFoundation)
        case (.tableau, .foundation):
            applyScore(.tableauToFoundation)
        case (.foundation, .tableau):
            applyScore(.foundationToTableau)
        default:
            break
        }
    }
}
