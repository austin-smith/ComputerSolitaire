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

    func handleKlondikeStockTap() {
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
