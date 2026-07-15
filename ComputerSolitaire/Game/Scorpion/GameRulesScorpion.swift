import Foundation

nonisolated enum ScorpionGameRules {
    /// Scorpion's landing rule: an empty pile takes only a king, and a face-up
    /// top takes the card one rank lower of the same suit.
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        guard let top = destinationPile.last else { return card.rank == .king }
        return top.isFaceUp
            && top.suit == card.suit
            && card.rank.rawValue == top.rank.rawValue - 1
    }

    /// The three-card stock may be dealt at any time; it is used exactly once.
    static func canDealFromStock(state: GameState) -> Bool {
        !state.stock.isEmpty
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

    /// What a resolution sweep did: how many runs it banked, and how many
    /// face-down cards those removals turned face up. The session scores both
    /// — a reveal is a reveal whether a move or a banked run exposed it.
    struct Resolution: Equatable {
        var bankedRunCount = 0
        var revealedCardCount = 0
    }

    /// Banks every complete run to the first empty foundation (Ace at the
    /// bottom, King on top), flipping the tops the removals expose, until no
    /// complete run remains: a removal or a dealt card can complete another.
    /// Returns what the sweep banked and revealed.
    @discardableResult
    static func resolveCompletedRuns(in state: inout GameState) -> Resolution {
        var resolution = Resolution()
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
                if state.tableau[pileIndex].last?.isFaceUp == false {
                    resolution.revealedCardCount += 1
                }
                AutoMoveAdvisor.flipExposedFaceDownTop(on: &state, pileIndex: pileIndex)
                resolution.bankedRunCount += 1
                didRemoveRun = true
            }
        }
        return resolution
    }

    /// Deals the stock's three cards face-up, one onto each of the first three
    /// piles left to right, then banks any runs the deal completed. Returns
    /// what the resolution sweep banked and revealed, or `nil` when the stock
    /// is already spent. Shared verbatim by the session, the planner, and the
    /// hint probe so simulated deals match real ones.
    static func dealStock(in state: inout GameState) -> Resolution? {
        guard canDealFromStock(state: state) else { return nil }
        let dealCount = state.stock.count
        for pileIndex in 0..<dealCount {
            var card = state.stock.removeLast()
            card.isFaceUp = true
            state.tableau[pileIndex].append(card)
        }
        return resolveCompletedRuns(in: &state)
    }
}
