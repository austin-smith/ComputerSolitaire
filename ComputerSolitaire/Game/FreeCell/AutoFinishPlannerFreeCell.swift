import Foundation

nonisolated extension AutoFinishPlanner {
    /// A necessary condition for a FreeCell foundation run, so the win
    /// simulation only runs on positions that could plausibly pass it.
    /// Auto-finish plays nothing but cascade tops (and free cells) onto the
    /// foundations, so a buried card can only reach its foundation after every
    /// same-suit card above it — and the foundation ascends, so each of those
    /// must outrank it. A cascade holding a same-suit pair whose deeper card
    /// is the lower rank can therefore never drain, and the position can never
    /// auto-finish. The check is monotone under the run's own moves (removing
    /// tops cannot create such a pair), so a run that starts available stays
    /// available step to step exactly as before.
    static func freeCellCascadesAllowFoundationRun(_ state: GameState) -> Bool {
        for pile in state.tableau {
            // Bottom to top, each suit's ranks must strictly descend; track
            // the lowest rank seen so far per suit and reject any card that
            // sits above a lower-ranked card of its own suit.
            var lowestRankBySuit: [Suit: Rank] = [:]
            for card in pile {
                if let lowest = lowestRankBySuit[card.suit], card.rank > lowest {
                    return false
                }
                lowestRankBySuit[card.suit] = card.rank
            }
        }
        return true
    }
}
