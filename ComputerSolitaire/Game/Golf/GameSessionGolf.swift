import Foundation

extension SolitaireViewModel {
    // MARK: Configuration

    /// Golf draws a single card to the waste. The scoring draw count keeps the
    /// draw-three basis the other stockless-choice variants use even though
    /// Golf's stroke scoring adds no time bonus, so the shared invariant that
    /// every variant defines a basis still holds.
    func configureGolfNewGame() {
        setStockDrawCount(DrawMode.one.rawValue)
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(min(1, state.waste.count))
        setInitialScore(golfBoardCardCount)
    }

    func configureGolfRedeal() {
        setScoringDrawCount(DrawMode.three.rawValue)
        setWasteDrawCount(min(1, state.waste.count))
        setInitialScore(golfBoardCardCount)
    }

    func sanitizeGolfRedealState(_ baseState: GameState) -> GameState {
        var sanitizedState = baseState
        sanitizedState.wasteDrawCount = min(1, sanitizedState.waste.count)
        return sanitizedState
    }

    /// The live Golf score: one stroke per card still on the board. Derived
    /// from the actual state (35 on a fresh deal) so restored redeals stay
    /// honest.
    var golfBoardCardCount: Int {
        state.tableau.reduce(0) { $0 + $1.count }
    }

    // MARK: Moves

    /// Executes the Golf move (`.waste`): plays the exposed card of a column
    /// onto the waste as one scored, undoable move. Each play removes one
    /// stroke; the play that clears the board also banks one bonus stroke per
    /// card left in the stock, making negative finals the best results.
    @discardableResult
    func performGolfMove(selection: Selection, to destination: Destination) -> Bool {
        guard let nextState = GolfGameRules.stateByApplying(
            selection: selection,
            destination: destination,
            to: state
        ) else { return false }

        clearHint()
        pushHistory(
            undoContext: UndoAnimationContext(
                action: .moveSelection,
                cardIDs: selection.cards.map(\.id)
            )
        )
        state = nextState
        incrementMovesCount()
        applyScore(.golfBoardPlay)
        if state.isWon {
            applyScore(.golfBoardClear(remainingStockCount: state.stock.count))
        }
        applyTimeBonusIfWon()
        self.selection = nil
        SoundManager.shared.play(.cardPlaced)
        refreshAutoFinishAvailability()
        return true
    }

    // MARK: Interaction

    /// A Golf card either plays onto the waste or it doesn't, so a tap
    /// auto-moves the exposed card and any other tap just gives failure
    /// feedback — there is no two-step select-then-tap flow.
    func handleGolfTableauTap(
        pile: [Card],
        pileIndex: Int,
        cardIndex: Int,
        card: Card
    ) -> Bool {
        HapticManager.shared.play(.cardPickUp)

        guard cardIndex == pile.count - 1 else {
            selection = nil
            HapticManager.shared.play(.invalidDrop)
            return true
        }

        let tappedSelection = Selection(
            source: .tableau(pile: pileIndex, index: cardIndex),
            cards: [card]
        )
        _ = queueBestAutoMove(for: tappedSelection)
        selection = nil
        return true
    }

    // MARK: Stock

    /// Flips one stock card onto the waste. Single pass: once the stock is
    /// empty the slot goes dead — Golf never recycles. The flip costs no
    /// strokes; its price is the board card it didn't play.
    func handleGolfStockTap() {
        clearHint()
        selection = nil
        isDragging = false
        pendingAutoMove = nil
        guard !state.stock.isEmpty else { return }
        drawFromStock()
    }

    // MARK: Match

    /// Whether the hole is over without a win: the stock is spent and no
    /// exposed card plays. Derived rather than stored — the check is exact
    /// and cheap for Golf — so persistence and undo need nothing extra.
    var isGolfHoleDead: Bool {
        gameVariant == .golf && !isWin && !HintAdvisor.anyPlayerMoveExists(in: state)
    }

    /// A hole ends won (board cleared) or dead (nothing left to play).
    var isGolfHoleOver: Bool {
        gameVariant == .golf && (isWin || isGolfHoleDead)
    }

    /// The match total as it stands right now: the banked holes plus the hole
    /// in play (whose strokes are its live score) — what the match would
    /// total if play stopped here. Once the ninth hole banks, the live score
    /// is already in the scorecard, so the sum drops out. The header's Match
    /// tile and the hole-complete overlay both read this, so they can never
    /// disagree.
    var golfLiveMatchTotal: Int {
        golfMatch.isComplete ? golfMatch.runningTotal : golfMatch.runningTotal + score
    }

    /// Banks the finished hole's strokes into the scorecard and moves the
    /// match forward: deals the next hole, or completes the match after the
    /// ninth. Nothing enters the scorecard or the match statistics until the
    /// player advances, so undoing out of a dead hole is always safe.
    func advanceGolfHole() {
        guard isGolfHoleOver, !golfMatch.isComplete else { return }
        // A dead hole finalizes as played-not-won here (a won hole already
        // finalized when the time bonus applied), recording its per-hole
        // statistics — including the completed hole's stroke score — through
        // the same funnel every variant's games end in.
        finalizeCurrentGameIfNeeded(didWin: isWin, endedAt: dateProvider.now)
        golfMatch.completedHoleScores.append(score)
        if golfMatch.isComplete {
            // Stay on the finished board; the match summary presents from
            // this persisted state, so quitting here re-presents it.
            if golfMatch.countsTowardStatistics {
                GameStatisticsStore.update(for: .golf) { stats in
                    stats.recordCompletedGolfMatch(total: golfMatch.runningTotal)
                }
            }
        } else {
            dealNextGolfHole()
        }
    }

    /// Resets the scorecard and deals the first hole of a fresh match.
    func startNewGolfMatch() {
        newGame(mode: .golf)
    }

    /// Deals the next hole through the shared new-game path while preserving
    /// the match — the one sanctioned exception to a fresh deal abandoning it.
    private func dealNextGolfHole() {
        let match = golfMatch
        newGame(mode: .golf)
        golfMatch = match
    }
}
