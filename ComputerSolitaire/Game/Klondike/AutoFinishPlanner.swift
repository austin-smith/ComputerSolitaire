import Foundation

/// Detects when the remaining game is a pure foundation run and produces the moves.
///
/// Klondike qualifies once the stock/waste are empty and every tableau card is face up;
/// Yukon once every tableau card is face up; FreeCell qualifies whenever repeatedly
/// playing eligible cards (from cascade tops and free cells) reaches a win in simulation;
/// Forty Thieves once its single-pass stock is spent, playing tableau tops and the
/// waste top. Canfield qualifies once its stock and waste are both spent, playing
/// tableau tops and the reserve top (with the compulsory reserve fill mirrored in
/// simulation).
nonisolated enum AutoFinishPlanner {
    struct AutoFinishMove {
        let selection: Selection
        let destination: Destination
    }

    static func canAutoFinish(in state: GameState) -> Bool {
        guard isAutoFinishCandidateState(state) else { return false }
        var simulatedState = state
        let maxSteps = simulatedState.tableau.reduce(0) { partialResult, pile in
            partialResult + pile.count
        } + simulatedState.freeCells.count + simulatedState.waste.count
            + simulatedState.reserve.count

        for _ in 0..<maxSteps {
            if simulatedState.isWon {
                return true
            }
            guard let move = nextAutoFinishMoveInternal(in: simulatedState),
                  applyAutoFinishMove(move, in: &simulatedState) else {
                return false
            }
        }

        return simulatedState.isWon
    }

    static func nextAutoFinishMove(in state: GameState) -> AutoFinishMove? {
        guard isAutoFinishCandidateState(state) else { return nil }
        return nextAutoFinishMoveInternal(in: state)
    }
}

nonisolated private extension AutoFinishPlanner {
    static func isAutoFinishCandidateState(_ state: GameState) -> Bool {
        guard !state.isWon else { return false }
        switch state.variant {
        case .klondike:
            guard state.stock.isEmpty, state.waste.isEmpty else { return false }
            return !state.tableau.joined().contains(where: { !$0.isFaceUp })
        case .freecell:
            return true
        case .yukon:
            return !state.tableau.joined().contains(where: { !$0.isFaceUp })
        case .spider, .scorpion:
            // Spider and Scorpion bank completed runs automatically; there is
            // never a foundation run left for auto-finish to play.
            return false
        case .pyramid:
            // Pyramid has no deterministic mop-up phase: which pair to remove
            // matters to the last move, so the game never auto-finishes.
            return false
        case .tripeaks:
            // TriPeaks has no deterministic mop-up phase either: play order
            // matters to the last card, so the game never auto-finishes.
            return false
        case .golf:
            // Golf has no deterministic mop-up phase either: play order
            // matters to the last card, so the game never auto-finishes.
            return false
        case .fortyThieves:
            // Every board card is face up, so once the single-pass stock is
            // spent the position is fully determined; the simulation below
            // still verifies the greedy run actually reaches a win.
            return state.stock.isEmpty
        case .canfield:
            // Recycling makes a live stock or waste an open choice, so both
            // must be spent; the reserve plays out deterministically from the
            // top. The simulation below verifies the greedy run reaches a win.
            return state.stock.isEmpty && state.waste.isEmpty
        }
    }

    static func nextAutoFinishMoveInternal(in state: GameState) -> AutoFinishMove? {
        var candidates: [(move: AutoFinishMove, rankValue: Int, sourceOrder: Int, foundationPile: Int)] = []

        for pileIndex in state.tableau.indices {
            guard let topIndex = state.tableau[pileIndex].indices.last else { continue }
            let card = state.tableau[pileIndex][topIndex]
            guard card.isFaceUp else { continue }

            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                guard GameRules.canMoveToFoundation(card: card, foundation: foundation, in: state)
                else { continue }

                let selection = Selection(
                    source: .tableau(pile: pileIndex, index: topIndex),
                    cards: [card]
                )
                candidates.append(
                    (
                        move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                        rankValue: foundationOrderValue(of: card, in: state),
                        sourceOrder: pileIndex,
                        foundationPile: foundationIndex
                    )
                )
            }
        }

        if state.variant == .freecell {
            for slot in state.freeCells.indices {
                guard let card = state.freeCells[slot] else { continue }
                for foundationIndex in state.foundations.indices {
                    let foundation = state.foundations[foundationIndex]
                    guard GameRules.canMoveToFoundation(card: card, foundation: foundation, in: state)
                    else { continue }

                    let selection = Selection(source: .freeCell(slot: slot), cards: [card])
                    candidates.append(
                        (
                            move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                            rankValue: foundationOrderValue(of: card, in: state),
                            sourceOrder: state.tableau.count + slot,
                            foundationPile: foundationIndex
                        )
                    )
                }
            }
        }

        if state.variant == .fortyThieves, let card = state.waste.last {
            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                guard GameRules.canMoveToFoundation(card: card, foundation: foundation, in: state)
                else { continue }

                let selection = Selection(source: .waste, cards: [card])
                candidates.append(
                    (
                        move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                        rankValue: card.rank.rawValue,
                        sourceOrder: state.tableau.count,
                        foundationPile: foundationIndex
                    )
                )
            }
        }

        if state.variant == .canfield, let card = state.reserve.last, card.isFaceUp {
            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                guard GameRules.canMoveToFoundation(card: card, foundation: foundation, in: state)
                else { continue }

                let selection = Selection(source: .reserve, cards: [card])
                candidates.append(
                    (
                        move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                        rankValue: foundationOrderValue(of: card, in: state),
                        sourceOrder: state.tableau.count,
                        foundationPile: foundationIndex
                    )
                )
            }
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.rankValue != rhs.rankValue {
                return lhs.rankValue < rhs.rankValue
            }
            if lhs.sourceOrder != rhs.sourceOrder {
                return lhs.sourceOrder < rhs.sourceOrder
            }
            return lhs.foundationPile < rhs.foundationPile
        }
        return sorted.first?.move
    }

    /// Lowest-needed-first ordering for the greedy run: the raw rank
    /// everywhere except Canfield, whose foundations start at a dealt base
    /// rank and wrap, so its "lowest" is the smallest offset above the base.
    static func foundationOrderValue(of card: Card, in state: GameState) -> Int {
        guard state.variant == .canfield,
              let base = CanfieldGameRules.baseRank(in: state) else {
            return card.rank.rawValue
        }
        return CanfieldGameRules.foundationOffset(of: card.rank, from: base)
    }

    @discardableResult
    static func applyAutoFinishMove(_ move: AutoFinishMove, in state: inout GameState) -> Bool {
        guard case .foundation(let foundationIndex) = move.destination,
              state.foundations.indices.contains(foundationIndex) else {
            return false
        }
        guard move.selection.cards.count == 1, let movingCard = move.selection.cards.first else {
            return false
        }
        guard GameRules.canMoveToFoundation(
            card: movingCard,
            foundation: state.foundations[foundationIndex],
            in: state
        ) else {
            return false
        }

        switch move.selection.source {
        case .tableau(let pileIndex, let cardIndex):
            guard state.tableau.indices.contains(pileIndex),
                  state.tableau[pileIndex].indices.contains(cardIndex),
                  cardIndex == state.tableau[pileIndex].count - 1,
                  state.tableau[pileIndex][cardIndex].id == movingCard.id else {
                return false
            }
            _ = state.tableau[pileIndex].popLast()
            if let newTopIndex = state.tableau[pileIndex].indices.last,
               !state.tableau[pileIndex][newTopIndex].isFaceUp {
                state.tableau[pileIndex][newTopIndex].isFaceUp = true
            }
            if state.variant == .canfield {
                CanfieldGameRules.refillEmptyPileFromReserve(on: &state, pileIndex: pileIndex)
            }

        case .freeCell(let slot):
            guard state.freeCells.indices.contains(slot),
                  state.freeCells[slot]?.id == movingCard.id else {
                return false
            }
            state.freeCells[slot] = nil

        case .waste:
            guard state.waste.last?.id == movingCard.id else { return false }
            _ = state.waste.popLast()
            state.wasteDrawCount = min(1, state.waste.count)

        case .reserve:
            guard state.reserve.last?.id == movingCard.id else { return false }
            _ = state.reserve.popLast()
            if let newTopIndex = state.reserve.indices.last {
                state.reserve[newTopIndex].isFaceUp = true
            }

        case .foundation, .pyramid, .triPeaks:
            return false
        }

        state.foundations[foundationIndex].append(movingCard)
        return true
    }
}
