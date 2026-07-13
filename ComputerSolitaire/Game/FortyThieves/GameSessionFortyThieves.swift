import Foundation

extension SolitaireViewModel {
    // MARK: Configuration

    /// Forty Thieves draws a single card to the waste. The scoring draw count
    /// keeps the draw-three basis the other stockless-choice variants use, so
    /// the shared invariant that every variant defines a time-bonus basis
    /// still holds.
    func configureFortyThievesNewGame() {
        setStockDrawCount(DrawMode.one.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(0)
    }

    func configureFortyThievesRedeal() {
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(min(1, state.waste.count))
    }

    func sanitizeFortyThievesRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = min(1, sanitizedState.waste.count)
        return sanitizedState
    }

    // MARK: Scoring

    func applyFortyThievesMoveScore(for source: Selection.Source, destination: Destination) {
        switch (source, destination) {
        case (.waste, .tableau):
            applyScore(.wasteToTableau)
        case (.waste, .foundation):
            applyScore(.wasteToFoundation)
        case (.tableau, .foundation):
            applyScore(.tableauToFoundation)
        default:
            break
        }
    }

    // MARK: Stock

    /// Flips one stock card onto the waste. Single pass: once the stock is
    /// empty the slot goes dead — Forty Thieves never recycles.
    func handleFortyThievesStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        guard !state.stock.isEmpty else { return }
        drawFromStock()
    }
}
