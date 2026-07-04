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
            if case .foundation = selection.source { continue }
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

/// Produces hints for both variants.
///
/// FreeCell hints come from the solver: the hint is the first move of an actual winning
/// line. The full line is cached keyed by position, so as long as the player follows it
/// (or plays ahead along it), subsequent hints are instant. Klondike hints come from the
/// bounded `KlondikePlanner` search.
final class HintPlanner {
    /// How long a single interactive hint request may spend searching.
    private static let freeCellSearchBudget: TimeInterval = 0.3
    private static let klondikeSearchBudget: TimeInterval = 0.15

    private var freeCellPlan: [String: FreeCellSolver.Move] = [:]

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
