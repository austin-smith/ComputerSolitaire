import Foundation

enum KlondikeHintAdvisor {
    typealias HintMoveResolver = (_ state: GameState, _ stockDrawCount: Int) -> HintAdvisor.HintMove?

    static func canRevealPlayableMoveViaStockTap(
        in state: GameState,
        stockDrawCount: Int,
        bestHintMove: HintMoveResolver
    ) -> Bool {
        var simulatedState = state
        let maxLookaheadSteps = stockTapLookaheadSteps(in: state, stockDrawCount: stockDrawCount)

        for _ in 0..<maxLookaheadSteps {
            guard let nextState = stockTapState(from: simulatedState, stockDrawCount: stockDrawCount) else {
                return false
            }
            simulatedState = nextState

            if bestHintMove(simulatedState, stockDrawCount) != nil {
                return true
            }
        }

        return false
    }
}

private extension KlondikeHintAdvisor {
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
