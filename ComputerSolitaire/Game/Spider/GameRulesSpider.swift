import Foundation

enum SpiderGameRules {
    /// Spider's landing rule: an empty pile takes any card, and a face-up top
    /// takes a card one rank lower regardless of suit.
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        guard let top = destinationPile.last else { return true }
        return top.isFaceUp && card.rank.rawValue == top.rank.rawValue - 1
    }

    /// Dealing a stock row requires a card in every pile.
    static func canDealFromStock(state: GameState) -> Bool {
        !state.stock.isEmpty && state.tableau.allSatisfy { !$0.isEmpty }
    }

    /// Index where a complete face-up King-to-Ace same-suit run starts at the
    /// top of the pile, or `nil` when the pile holds none.
    static func completedRunStartIndex(in pile: [Card]) -> Int? {
        let runLength = Rank.allCases.count
        guard pile.count >= runLength else { return nil }
        let startIndex = pile.count - runLength
        let run = Array(pile[startIndex...])
        guard run.first?.rank == .king else { return nil }
        guard SharedGameRules.isDescendingSameSuitRun(run) else { return nil }
        return startIndex
    }

    /// Banks every complete run to the first empty foundation (Ace at the
    /// bottom, King on top), flipping the tops the removals expose, until no
    /// complete run remains: a removal or a dealt card can complete another.
    /// Returns how many runs were banked.
    @discardableResult
    static func resolveCompletedRuns(in state: inout GameState) -> Int {
        var completedRunCount = 0
        var didRemoveRun = true
        while didRemoveRun {
            didRemoveRun = false
            for pileIndex in state.tableau.indices {
                guard let startIndex = completedRunStartIndex(in: state.tableau[pileIndex]),
                      let foundationIndex = state.foundations.firstIndex(where: \.isEmpty) else {
                    continue
                }
                let run = Array(state.tableau[pileIndex][startIndex...])
                state.tableau[pileIndex].removeSubrange(startIndex...)
                state.foundations[foundationIndex] = run.reversed()
                AutoMoveAdvisor.flipExposedFaceDownTop(on: &state, pileIndex: pileIndex)
                completedRunCount += 1
                didRemoveRun = true
            }
        }
        return completedRunCount
    }

    /// Deals one face-up stock card onto each pile, left to right, then banks
    /// any runs the deal completed. Returns how many runs were banked, or
    /// `nil` when dealing is illegal. Shared verbatim by the session, the
    /// planner, and the hint probe so simulated deals match real ones.
    static func dealStockRow(in state: inout GameState) -> Int? {
        guard canDealFromStock(state: state) else { return nil }
        for pileIndex in state.tableau.indices {
            var card = state.stock.removeLast()
            card.isFaceUp = true
            state.tableau[pileIndex].append(card)
        }
        return resolveCompletedRuns(in: &state)
    }
}
