import Foundation

extension SolitaireViewModel {
    // MARK: Configuration

    /// Canfield always turns three cards to the waste, with unlimited
    /// recycles; there is no draw-mode choice.
    func configureCanfieldNewGame() {
        setStockDrawCount(DrawMode.three.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(0)
    }

    func configureCanfieldRedeal() {
        setScoringDrawCount(DrawMode.three.rawValue)
        // The exposed waste top is always available, so the fan floors at one
        // card while the waste holds any.
        let clampedWasteDrawCount = min(
            max(min(1, state.waste.count), state.wasteDrawCount),
            min(stockDrawCount, state.waste.count)
        )
        setWasteDrawCount(clampedWasteDrawCount)
    }

    func sanitizeCanfieldRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = min(
            max(min(1, sanitizedState.waste.count), sanitizedState.wasteDrawCount),
            min(DrawMode.three.rawValue, sanitizedState.waste.count)
        )
        return sanitizedState
    }

    // MARK: Scoring

    func applyCanfieldMoveScore(for source: Selection.Source, destination: Destination) {
        switch (source, destination) {
        case (.waste, .tableau):
            applyScore(.wasteToTableau)
        case (.waste, .foundation):
            applyScore(.wasteToFoundation)
        case (.tableau, .foundation):
            applyScore(.tableauToFoundation)
        case (.reserve, .tableau):
            applyScore(.reserveToTableau)
        case (.reserve, .foundation):
            applyScore(.reserveToFoundation)
        default:
            break
        }
    }

    // MARK: Stock

    /// Turns three cards onto the waste; with the stock out, a tap turns the
    /// waste over to form the new stock. Redeals are unlimited.
    func handleCanfieldStockTap() {
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

    // MARK: Reserve

    func handleReserveTap() {
        guard state.variant == .canfield else { return }
        guard let top = state.reserve.last, top.isFaceUp else { return }
        HapticManager.shared.play(.cardPickUp)

        let reserveSelection = Selection(source: .reserve, cards: [top])
        if queueBestAutoMove(for: reserveSelection) {
            return
        }
        if selection?.source == .reserve {
            selection = nil
            return
        }
        isDragging = false
        selection = reserveSelection
    }

    @discardableResult
    func startDragFromReserve() -> Bool {
        guard state.variant == .canfield else { return false }
        guard let top = state.reserve.last, top.isFaceUp else { return false }
        clearHint()
        selection = Selection(source: .reserve, cards: [top])
        isDragging = true
        return true
    }

    /// The compulsory space fill after a tableau source removal, with the
    /// session-side score and feedback the advisor's pure version stays
    /// silent about. The fill scores like any reserve-to-tableau play — the
    /// rules forcing the move does not change what the player gained, and
    /// Klondike's compulsory flip scores through its automatic path the same
    /// way.
    func refillCanfieldSpaceFromReserve(in pileIndex: Int) {
        guard state.tableau.indices.contains(pileIndex),
              state.tableau[pileIndex].isEmpty,
              !state.reserve.isEmpty else { return }
        CanfieldGameRules.refillEmptyPileFromReserve(on: &state, pileIndex: pileIndex)
        applyScore(.reserveToTableau)
        SoundManager.shared.play(.cardPlaced)
    }
}
