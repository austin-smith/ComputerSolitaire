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

        if state.variant == .klondike,
           KlondikeHintAdvisor.canRevealPlayableMoveViaStockTap(
            in: state,
            stockDrawCount: stockDrawCount,
            bestHintMove: bestHintMove(in:stockDrawCount:)
           ) {
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
