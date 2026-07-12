import Foundation

extension SolitaireViewModel {
    // MARK: Configuration

    /// Pyramid draws a single card to the waste; time-bonus scoring keeps the
    /// draw-three basis the other stockless-choice variants use.
    func configurePyramidNewGame() {
        setStockDrawCount(DrawMode.one.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(0)
    }

    func configurePyramidRedeal() {
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(min(1, state.waste.count))
    }

    func sanitizePyramidRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = min(1, sanitizedState.waste.count)
        sanitizedState.wasteRecyclesUsed = min(
            max(0, sanitizedState.wasteRecyclesUsed),
            PyramidGameRules.maxWasteRecycles
        )
        return sanitizedState
    }

    // MARK: Moves

    /// Executes the Pyramid destinations (`.pyramid`, `.waste`, `.discard`): removes
    /// a rank-13 pair or a lone King to the discard as one scored, undoable move.
    @discardableResult
    func performPyramidMove(selection: Selection, to destination: Destination) -> Bool {
        guard let nextState = PyramidGameRules.stateByApplying(
            selection: selection,
            destination: destination,
            to: state
        ) else { return false }

        clearHint()
        let removedCardIDs = nextState.discard.suffix(
            nextState.discard.count - state.discard.count
        ).map(\.id)
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .moveSelection,
                cardIDs: removedCardIDs
            )
        )
        state = nextState
        incrementMovesCount()
        applyPyramidMoveScore(for: destination)
        applyTimeBonusIfWon()
        self.selection = nil
        SoundManager.shared.play(.cardPlaced)
        refreshAutoFinishAvailability()
        return true
    }

    func applyPyramidMoveScore(for destination: Destination) {
        switch destination {
        case .pyramid, .waste:
            applyScore(.removePyramidPair)
        case .discard:
            applyScore(.removePyramidKing)
        case .foundation, .tableau, .freeCell:
            break
        }
    }

    // MARK: Interaction

    func handlePyramidTap(index: Int) {
        guard state.pyramid.indices.contains(index), let card = state.pyramid[index] else { return }
        HapticManager.shared.play(.cardPickUp)

        // An active selection pairing with the tapped card wins over auto-moving
        // it, so tap-select-then-tap-partner behaves as expected.
        if selection != nil, tryMoveSelection(to: .pyramid(index)) {
            return
        }

        let tappedSelection = Selection(source: .pyramid(index: index), cards: [card])
        if selection?.source == tappedSelection.source {
            selection = nil
            return
        }

        guard PyramidGameRules.isSelectable(index: index, in: state.pyramid) else {
            selection = nil
            HapticManager.shared.play(.invalidDrop)
            return
        }

        if queueBestAutoMove(for: tappedSelection) {
            return
        }

        isDragging = false
        selection = tappedSelection
    }

    @discardableResult
    func startDragFromPyramid(index: Int) -> Bool {
        guard state.pyramid.indices.contains(index),
              let card = state.pyramid[index],
              PyramidGameRules.isSelectable(index: index, in: state.pyramid) else { return false }
        clearHint()
        selection = Selection(source: .pyramid(index: index), cards: [card])
        isDragging = true
        return true
    }

    // MARK: Stock

    func handlePyramidStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        if state.stock.isEmpty {
            recyclePyramidWaste()
        } else {
            drawFromStock()
        }
    }

    /// Turns the waste back into the stock, consuming one of the limited recycles.
    /// The pass limit is the cost, so no score penalty applies.
    func recyclePyramidWaste() {
        guard PyramidGameRules.canRecycleWaste(in: state) else { return }
        clearHint()
        let animatedWasteIDs = [state.waste.last?.id].compactMap { $0 }
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
        state.wasteRecyclesUsed += 1
        setWasteDrawCount(0)
        incrementMovesCount()
        SoundManager.shared.play(.wasteRecycleToStock)
        HapticManager.shared.play(.wasteRecycle)
        refreshAutoFinishAvailability()
    }

    var pyramidWasteRecyclesRemaining: Int {
        max(0, PyramidGameRules.maxWasteRecycles - state.wasteRecyclesUsed)
    }
}
