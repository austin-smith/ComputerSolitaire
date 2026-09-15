import Foundation

nonisolated protocol HintSearching: Sendable {
    func bestHint(in state: GameState, stockDrawCount: Int) async throws -> HintAdvisor.Hint?
}

/// Owns one session's mutable plan caches. Searching never suspends inside
/// this actor, so subsequent requests cannot interleave with cache updates.
actor HintSearchWorker: HintSearching {
    private let planner = HintPlanner()

    func bestHint(in state: GameState, stockDrawCount: Int) throws -> HintAdvisor.Hint? {
        try Task.checkCancellation()
        let hint = planner.bestHint(in: state, stockDrawCount: stockDrawCount)
        try Task.checkCancellation()
        return hint
    }
}
