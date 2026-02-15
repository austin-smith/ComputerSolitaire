import Foundation

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
        }

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
    static func isAutoFinishCandidateState(_ state: GameState) -> Bool {
        guard !isWin(state) else { return false }
        guard state.stock.isEmpty, state.waste.isEmpty else { return false }
        return !state.tableau.joined().contains(where: { !$0.isFaceUp })
    }

    static func isWin(_ state: GameState) -> Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
    }

    static func nextAutoFinishMoveInternal(in state: GameState) -> AutoFinishMove? {
        var candidates: [(move: AutoFinishMove, rankValue: Int, tableauPile: Int, foundationPile: Int)] = []

        for pileIndex in state.tableau.indices {
            guard let topIndex = state.tableau[pileIndex].indices.last else { continue }
            let card = state.tableau[pileIndex][topIndex]
            guard card.isFaceUp else { continue }

            for foundationIndex in state.foundations.indices {
                let foundation = state.foundations[foundationIndex]
                guard GameRules.canMoveToFoundation(card: card, foundation: foundation) else { continue }

                let selection = Selection(
                    source: .tableau(pile: pileIndex, index: topIndex),
                    cards: [card]
                )
                candidates.append(
                    (
                        move: AutoFinishMove(selection: selection, destination: .foundation(foundationIndex)),
                        rankValue: card.rank.rawValue,
                        tableauPile: pileIndex,
                        foundationPile: foundationIndex
                    )
                )
            }
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.rankValue != rhs.rankValue {
                return lhs.rankValue < rhs.rankValue
            }
            if lhs.tableauPile != rhs.tableauPile {
                return lhs.tableauPile < rhs.tableauPile
            }
            return lhs.foundationPile < rhs.foundationPile
        }
        return sorted.first?.move
    }

    @discardableResult
    static func applyAutoFinishMove(_ move: AutoFinishMove, in state: inout GameState) -> Bool {
        guard case .tableau(let pileIndex, let cardIndex) = move.selection.source,
              case .foundation(let foundationIndex) = move.destination else {
            return false
        }
        guard state.tableau.indices.contains(pileIndex),
              state.foundations.indices.contains(foundationIndex),
              state.tableau[pileIndex].indices.contains(cardIndex),
              cardIndex == state.tableau[pileIndex].count - 1 else {
            return false
        }
        guard let movingCard = state.tableau[pileIndex].last else { return false }
        guard move.selection.cards.count == 1,
              move.selection.cards[0].id == movingCard.id else {
            return false
        }
        guard GameRules.canMoveToFoundation(card: movingCard, foundation: state.foundations[foundationIndex]) else {
            return false
        }

        _ = state.tableau[pileIndex].popLast()
        if let newTopIndex = state.tableau[pileIndex].indices.last,
           !state.tableau[pileIndex][newTopIndex].isFaceUp {
            state.tableau[pileIndex][newTopIndex].isFaceUp = true
        }
        state.foundations[foundationIndex].append(movingCard)
        return true
    }
}
