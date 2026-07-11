import Foundation

/// Detects when the remaining game is a pure foundation run and produces the moves.
///
/// Klondike qualifies once the stock/waste are empty and every tableau card is face up;
/// FreeCell qualifies whenever repeatedly playing eligible cards (from cascade tops and
/// free cells) reaches a win in simulation.
enum AutoFinishPlanner {
    struct AutoFinishMove {
        let selection: Selection
        let destination: Destination
    }

    static func canAutoFinish(in state: GameState) -> Bool {
        guard isAutoFinishCandidateState(state) else { return false }
        var simulatedState = state
        let maxSteps = simulatedState.tableau.reduce(0) { partialResult, pile in
            partialResult + pile.count
        } + simulatedState.freeCells.count

        for _ in 0..<maxSteps {
            if isWin(simulatedState) {
                return true
            }
            guard let move = nextAutoFinishMoveInternal(in: simulatedState),
                  applyAutoFinishMove(move, in: &simulatedState) else {
                return false
            }
        }

        return isWin(simulatedState)
    }

    static func nextAutoFinishMove(in state: GameState) -> AutoFinishMove? {
        guard isAutoFinishCandidateState(state) else { return nil }
        return nextAutoFinishMoveInternal(in: state)
    }
}

private extension AutoFinishPlanner {
    struct Candidate {
        let move: AutoFinishMove
        let rankValue: Int
        let sourceOrder: Int
        let foundationPile: Int
    }

    static func isAutoFinishCandidateState(_ state: GameState) -> Bool {
        guard !isWin(state) else { return false }
        switch state.variant {
        case .klondike:
            guard state.stock.isEmpty, state.waste.isEmpty else { return false }
            return !state.tableau.joined().contains(where: { !$0.isFaceUp })
        case .freecell:
            return true
        }
    }

    static func isWin(_ state: GameState) -> Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
    }

    static func nextAutoFinishMoveInternal(in state: GameState) -> AutoFinishMove? {
        var candidates: [Candidate] = []

        for pileIndex in state.tableau.indices {
            candidates.append(contentsOf: tableauCandidates(in: state, pileIndex: pileIndex))
        }

        if state.variant == .freecell {
            for slot in state.freeCells.indices {
                candidates.append(contentsOf: freeCellCandidates(in: state, slot: slot))
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

    static func tableauCandidates(in state: GameState, pileIndex: Int) -> [Candidate] {
        guard let topIndex = state.tableau[pileIndex].indices.last else { return [] }
        let card = state.tableau[pileIndex][topIndex]
        guard card.isFaceUp else { return [] }
        let selection = Selection(source: .tableau(pile: pileIndex, index: topIndex), cards: [card])
        return foundationCandidates(
            for: card,
            selection: selection,
            sourceOrder: pileIndex,
            in: state
        )
    }

    static func freeCellCandidates(in state: GameState, slot: Int) -> [Candidate] {
        guard let card = state.freeCells[slot] else { return [] }
        let selection = Selection(source: .freeCell(slot: slot), cards: [card])
        return foundationCandidates(
            for: card,
            selection: selection,
            sourceOrder: state.tableau.count + slot,
            in: state
        )
    }

    static func foundationCandidates(
        for card: Card,
        selection: Selection,
        sourceOrder: Int,
        in state: GameState
    ) -> [Candidate] {
        state.foundations.indices.compactMap { foundationIndex in
            let foundation = state.foundations[foundationIndex]
            guard GameRules.canMoveToFoundation(card: card, foundation: foundation) else { return nil }
            return Candidate(
                move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                rankValue: card.rank.rawValue,
                sourceOrder: sourceOrder,
                foundationPile: foundationIndex
            )
        }
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
        guard GameRules.canMoveToFoundation(card: movingCard, foundation: state.foundations[foundationIndex]) else {
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

        case .freeCell(let slot):
            guard state.freeCells.indices.contains(slot),
                  state.freeCells[slot]?.id == movingCard.id else {
                return false
            }
            state.freeCells[slot] = nil

        case .waste, .foundation:
            return false
        }

        state.foundations[foundationIndex].append(movingCard)
        return true
    }
}
