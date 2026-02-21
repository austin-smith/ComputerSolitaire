import Foundation

enum HintAdvisor {
    enum Hint: Equatable {
        case move(HintMove)
        case stockTap
    }

    struct HintMove: Equatable {
        let selection: Selection
        let destination: Destination
    }

    static func bestHint(in state: GameState, stockDrawCount: Int) -> Hint? {
        if let move = bestHintMove(in: state, stockDrawCount: stockDrawCount) {
            return .move(move)
        }

        if canRevealPlayableMoveViaStockTap(in: state, stockDrawCount: stockDrawCount) {
            return .stockTap
        }

        return nil
    }

    static func bestHintMove(in state: GameState, stockDrawCount: Int) -> HintMove? {
        var bestChoice: (selection: Selection, evaluation: MoveEvaluation)?

        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            guard let evaluation = AutoMoveAdvisor.bestAdvisableMoveEvaluation(
                for: selection,
                in: state,
                stockDrawCount: stockDrawCount
            ) else {
                continue
            }

            if let currentBest = bestChoice {
                if MoveEvaluationRanking.isBetter(evaluation, than: currentBest.evaluation) {
                    bestChoice = (selection: selection, evaluation: evaluation)
                }
            } else {
                bestChoice = (selection: selection, evaluation: evaluation)
            }
        }

        guard let bestChoice else { return nil }
        return HintMove(
            selection: bestChoice.selection,
            destination: bestChoice.evaluation.destination
        )
    }
}

private extension HintAdvisor {
    static func canRevealPlayableMoveViaStockTap(in state: GameState, stockDrawCount: Int) -> Bool {
        var simulatedState = state
        let maxLookaheadSteps = stockTapLookaheadSteps(in: state, stockDrawCount: stockDrawCount)

        for _ in 0..<maxLookaheadSteps {
            guard let nextState = stockTapState(from: simulatedState, stockDrawCount: stockDrawCount) else {
                return false
            }
            simulatedState = nextState

            if bestHintMove(in: simulatedState, stockDrawCount: stockDrawCount) != nil {
                return true
            }
        }

        return false
    }

    static func stockTapLookaheadSteps(in state: GameState, stockDrawCount: Int) -> Int {
        let totalCardsInStockCycle = state.stock.count + state.waste.count
        guard totalCardsInStockCycle > 0 else { return 0 }

        let drawCount = max(1, stockDrawCount)
        let drawsPerPass = (totalCardsInStockCycle + drawCount - 1) / drawCount

        // One pass explores all draw groups in the current cycle.
        // A second pass covers cases where recycle state and draw grouping interact.
        return (drawsPerPass * 2) + 2
    }

    static func stockTapState(from state: GameState, stockDrawCount: Int) -> GameState? {
        var nextState = state

        if !nextState.stock.isEmpty {
            let drawCount = min(max(1, stockDrawCount), nextState.stock.count)
            for _ in 0..<drawCount {
                var card = nextState.stock.removeLast()
                card.isFaceUp = true
                nextState.waste.append(card)
            }
            nextState.wasteDrawCount = drawCount
            return nextState
        }

        guard !nextState.waste.isEmpty else { return nil }
        var recycledStock: [Card] = []
        for card in nextState.waste.reversed() {
            var recycledCard = card
            recycledCard.isFaceUp = false
            recycledStock.append(recycledCard)
        }
        nextState.stock = recycledStock
        nextState.waste.removeAll()
        nextState.wasteDrawCount = 0
        return nextState
    }
}
