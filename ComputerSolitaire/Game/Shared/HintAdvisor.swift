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

    /// Cheap check that some player action exists; used to enable the hint button
    /// after every move without paying for a full hint search.
    static func anyPlayerMoveExists(in state: GameState) -> Bool {
        if state.variant == .klondike, !state.stock.isEmpty || !state.waste.isEmpty {
            return true
        }
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            // Foundation rollbacks only count as available moves where the hint
            // stack can actually turn one into a hint: Yukon's planner searches
            // rollbacks (one can be the only rescue), while the Klondike planner
            // and FreeCell solver never suggest them.
            if case .foundation = selection.source, state.variant != .yukon {
                continue
            }
            if !AutoMoveAdvisor.legalDestinations(for: selection, in: state).isEmpty {
                return true
            }
        }
        return false
    }

    /// One-shot hint without plan caching, for tests and tools. Interactive callers
    /// should hold a `HintPlanner` so consecutive hints reuse the solved line.
    static func bestHint(in state: GameState, stockDrawCount: Int) -> Hint? {
        HintPlanner().bestHint(in: state, stockDrawCount: stockDrawCount)
    }
}

/// Produces hints for every variant.
///
/// FreeCell hints come from the solver: the hint is the first move of an actual winning
/// line. Klondike hints come from the bounded `KlondikePlanner` search, re-run per
/// request. Yukon hints come from `YukonPlanner`'s best improving line, cached like
/// FreeCell's: every Yukon tableau move is reversible until a card flips, so re-search
/// after each move can oscillate between equally attractive lines, while following one
/// cached line ratchets the position strictly forward. Cached lines are keyed by
/// position, so as long as the player follows one (or plays ahead along it),
/// subsequent hints are instant.
///
/// When no line is found, the variants deliberately differ. FreeCell falls back to
/// `TapMovePolicy`: its solver misses are usually winnable positions (~99% of deals
/// are), so a constructive nudge keeps a rescuable game moving. Yukon returns nil:
/// its planner misses are positions with no measurable progress anywhere in a large
/// searched region — a nudge there has never been observed to rescue a game and a
/// deterministic one shuttles a card back and forth, so a Yukon hint is always the
/// first move of a verified improving line, or silence (like Klondike's planner).
final class HintPlanner {
    /// How long a single interactive hint request may spend searching.
    private static let freeCellSearchBudget: TimeInterval = 0.3
    private static let klondikeSearchBudget: TimeInterval = 0.15
    private static let yukonSearchBudget: TimeInterval = 0.25

    private var freeCellPlan: [String: FreeCellSolver.Move] = [:]
    private var yukonPlan: [String: YukonPlanner.PlannedMove] = [:]

    func bestHint(in state: GameState, stockDrawCount: Int) -> HintAdvisor.Hint? {
        switch state.variant {
        case .klondike:
            return KlondikePlanner.bestHint(
                in: state,
                stockDrawCount: stockDrawCount,
                limits: KlondikePlanner.Limits(
                    deadline: Date().addingTimeInterval(Self.klondikeSearchBudget)
                )
            )
        case .freecell:
            return freeCellHint(in: state)
        case .yukon:
            return yukonHint(in: state)
        }
    }
}

private extension HintPlanner {
    func freeCellHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = FreeCellSolver.stateKey(for: state)
        if let hint = materializedHint(for: key, in: state) {
            return hint
        }

        freeCellPlan.removeAll()
        let limits = FreeCellSolver.Limits(
            deadline: Date().addingTimeInterval(Self.freeCellSearchBudget)
        )
        if let solution = FreeCellSolver.solve(state, limits: limits) {
            freeCellPlan = FreeCellSolver.keyedMoves(along: solution, from: state)
            if let hint = materializedHint(for: key, in: state) {
                return hint
            }
        }

        // No winning line found (lost position or budget exceeded): still point at the
        // most constructive legal move rather than shrugging.
        guard let fallback = TapMovePolicy.bestMove(in: state) else { return nil }
        return .move(
            HintAdvisor.HintMove(selection: fallback.selection, destination: fallback.destination)
        )
    }

    func yukonHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = YukonPlanner.stateKey(for: state)
        if let hint = plannedYukonHint(for: key, in: state) {
            return hint
        }

        yukonPlan.removeAll()
        let limits = YukonPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.yukonSearchBudget)
        )
        switch YukonPlanner.bestLine(in: state, limits: limits) {
        case .line(let line):
            yukonPlan = YukonPlanner.keyedMoves(along: line, from: state)
            return plannedYukonHint(for: key, in: state)

        case .noProgress:
            // Exhaustion proves the position is stuck; truncation means a large
            // searched region held no measurable progress, which is empirically just
            // as dead. Either way there is no move worth pointing at (see the class
            // comment for why Yukon does not fall back to a nudge). The hint button
            // re-enables after the player's next move.
            return nil
        }
    }

    func plannedYukonHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        guard let planned = yukonPlan[key],
              AutoMoveAdvisor.selectionMatchesState(planned.selection, in: state),
              AutoMoveAdvisor.legalDestinations(for: planned.selection, in: state)
                  .contains(planned.destination) else {
            return nil
        }
        return .move(
            HintAdvisor.HintMove(selection: planned.selection, destination: planned.destination)
        )
    }

    func materializedHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        guard let planned = freeCellPlan[key],
              let move = FreeCellSolver.materialize(planned, in: state) else {
            return nil
        }
        return .move(
            HintAdvisor.HintMove(selection: move.selection, destination: move.destination)
        )
    }
}
