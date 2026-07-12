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

    func handleKlondikeStockTap() {
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
        if scoringDrawCount == DrawMode.one.rawValue {
            applyScore(.recycleWasteInDrawOne)
        }
        SoundManager.shared.play(.wasteRecycleToStock)
        HapticManager.shared.play(.wasteRecycle)
        refreshAutoFinishAvailability()
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
