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
        if state.variant == .pyramid {
            if !state.stock.isEmpty || PyramidGameRules.canRecycleWaste(in: state) {
                return true
            }
        }
        if state.variant == .spider, SpiderGameRules.canDealFromStock(state: state) {
            return true
        }
        if state.variant == .scorpion, ScorpionGameRules.canDealFromStock(state: state) {
            return true
        }
        if state.variant == .tripeaks, !state.stock.isEmpty {
            return true
        }
        if state.variant == .golf, !state.stock.isEmpty {
            return true
        }
        if state.variant == .fortyThieves, !state.stock.isEmpty {
            return true
        }
        if state.variant == .canfield, !state.stock.isEmpty || !state.waste.isEmpty {
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
/// cached line ratchets the position strictly forward. Spider hints work like Yukon's
/// (its tableau moves are just as reversible until a flip, deal, or completed run),
/// with `SpiderPlanner` lines that may include stock deals. Cached lines are keyed by
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
/// Spider returns a stock-deal hint when its tableau holds no improving line but a
/// deal is legal — dealing is then the only way forward — and silence otherwise.
/// Pyramid hints come from `PyramidPlanner`'s exact search and are cached like
/// Yukon's; on unwinnable deals (common in Pyramid) they follow the max-clear line
/// rather than going silent, because players still play lost deals for cards
/// cleared and the solver knows the best continuation. Pyramid's nil is reserved
/// for positions where not one more pyramid card is clearable. The ratchet is
/// loop-free by construction: every Pyramid move advances a monotone quantity
/// (removals shrink the board, draws advance the stock, resets spend passes), so a
/// followed line can never revisit a position.
/// TriPeaks hints come from `TriPeaksPlanner`'s exact search and behave exactly
/// like Pyramid's: winning lines when the deal is winnable, the max-clear line on
/// unwinnable deals, nil only when not one more peak card is clearable. Its
/// ratchet is the strongest of any variant — every TriPeaks move consumes a card
/// (plays shrink the board, draws shrink the stock), so a followed line can never
/// revisit a position.
/// Golf hints come from `GolfPlanner`'s exact search and behave exactly like
/// TriPeaks': winning lines when the deal is winnable, the max-clear line on
/// unwinnable deals (common under strict no-wraparound rules), nil only when
/// not one more column card is clearable. Its ratchet matches TriPeaks' —
/// every Golf move consumes a card — so a followed line can never revisit a
/// position.
/// Forty Thieves hints work like Spider's: cached `FortyThievesPlanner`
/// improving lines that may include stock taps, followed to their end before
/// re-planning (its single-card tableau moves are just as reversible until a
/// card banks or the stock turns). When no improving line exists but stock
/// remains, the fallback is a single stock tap — unlike Spider's deal
/// preparation it costs nothing and strictly shrinks the stock, so it can
/// never cycle — and silence comes only when the stock is out and nothing
/// searched improves.
/// Scorpion hints work like Spider's: `ScorpionPlanner` lines (which may cross
/// the single stock deal) are cached and followed. When the tableau holds no
/// improving line but the stock remains, the hint is the deal itself — it is
/// legal at any time with no preparation needed, and holding it until the
/// tableau is provably stuck is exactly the strong player's timing. Silence is
/// reserved for positions with no line and no stock.
/// Canfield hints work like Forty Thieves': cached `CanfieldPlanner` improving
/// lines that may include stock taps, followed to their end before
/// re-planning. The one difference recycling makes is in the fallback: a
/// Canfield tap can cycle back to an earlier position, so when the planner's
/// search was *exhaustive* — which, taps and recycles included, is a proof the
/// position can never progress — the hint is silence, not a tap that would
/// churn a dead game forever. A truncated no-progress still falls back to the
/// tap, mirroring Forty Thieves' measured rationale.
final class HintPlanner {
    /// How long a single interactive hint request may spend searching.
    private static let freeCellSearchBudget: TimeInterval = 0.3
    private static let klondikeSearchBudget: TimeInterval = 0.15
    private static let yukonSearchBudget: TimeInterval = 0.25
    private static let spiderSearchBudget: TimeInterval = 0.3
    private static let pyramidSearchBudget: TimeInterval = 0.3
    private static let triPeaksSearchBudget: TimeInterval = 0.3
    /// Golf's exact searches are the largest of the planners (see
    /// `GolfPlanner.Limits`), so its clip is looser: a half-second think on
    /// the rare hard deal beats truncating a provably winnable position into
    /// a best-effort line.
    private static let golfSearchBudget: TimeInterval = 0.5
    private static let fortyThievesSearchBudget: TimeInterval = 0.3
    private static let scorpionSearchBudget: TimeInterval = 0.25
    private static let canfieldSearchBudget: TimeInterval = 0.3

    private var freeCellPlan: [String: FreeCellSolver.Move] = [:]
    private var yukonPlan: [String: YukonPlanner.PlannedMove] = [:]
    private var spiderPlan: [String: SpiderPlanner.PlannedAction] = [:]
    private var pyramidPlan: [String: PyramidPlanner.Move] = [:]
    private var triPeaksPlan: [String: TriPeaksPlanner.Move] = [:]
    private var golfPlan: [String: GolfPlanner.Move] = [:]
    private var fortyThievesPlan: [String: FortyThievesPlanner.PlannedAction] = [:]
    private var scorpionPlan: [String: ScorpionPlanner.PlannedAction] = [:]
    private var canfieldPlan: [String: CanfieldPlanner.PlannedAction] = [:]

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
        case .spider:
            return spiderHint(in: state)
        case .pyramid:
            return pyramidHint(in: state)
        case .tripeaks:
            return triPeaksHint(in: state)
        case .golf:
            return golfHint(in: state)
        case .fortyThieves:
            return fortyThievesHint(in: state)
        case .scorpion:
            return scorpionHint(in: state)
        case .canfield:
            return canfieldHint(in: state)
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

    func pyramidHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = PyramidPlanner.stateKey(for: state)
        if let hint = plannedPyramidHint(for: key, in: state) {
            return hint
        }

        pyramidPlan.removeAll()
        let limits = PyramidPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.pyramidSearchBudget)
        )
        switch PyramidPlanner.bestLine(in: state, limits: limits) {
        case .winningLine(let line), .bestEffortLine(let line, _):
            pyramidPlan = PyramidPlanner.keyedMoves(along: line, from: state)
            return plannedPyramidHint(for: key, in: state)

        case .noProgress:
            // Exhaustion proves not one more pyramid card is clearable; truncation
            // means a large searched region held none. Either way every remaining
            // action is provably futile stock-churning, so silence is the honest
            // answer. The hint button re-enables after the player's next move.
            return nil
        }
    }

    func plannedPyramidHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        // materialize re-validates the cached move against the live state.
        guard let move = pyramidPlan[key] else { return nil }
        return PyramidPlanner.materialize(move, in: state)
    }

    func triPeaksHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = TriPeaksPlanner.stateKey(for: state)
        if let hint = plannedTriPeaksHint(for: key, in: state) {
            return hint
        }

        triPeaksPlan.removeAll()
        let limits = TriPeaksPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.triPeaksSearchBudget)
        )
        switch TriPeaksPlanner.bestLine(in: state, limits: limits) {
        case .winningLine(let line), .bestEffortLine(let line, _):
            triPeaksPlan = TriPeaksPlanner.keyedMoves(along: line, from: state)
            return plannedTriPeaksHint(for: key, in: state)

        case .noProgress:
            // A proof, not a budget artifact: any clearable line registers
            // within the search's first ~two dozen expansions (a root play
            // pops immediately; otherwise only draws are legal, a chain of at
            // most 23, and a draw-enabled play pops right after its draw), so
            // no-progress is only ever reached by exhausting that region —
            // far under the interactive budget. Every remaining action is
            // provably futile stock-churning and silence is the honest
            // answer. The hint button re-enables after the player's next move.
            return nil
        }
    }

    func plannedTriPeaksHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        // materialize re-validates the cached move against the live state.
        guard let move = triPeaksPlan[key] else { return nil }
        return TriPeaksPlanner.materialize(move, in: state)
    }

    func golfHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = GolfPlanner.stateKey(for: state)
        if let hint = plannedGolfHint(for: key, in: state) {
            return hint
        }

        golfPlan.removeAll()
        let limits = GolfPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.golfSearchBudget)
        )
        switch GolfPlanner.bestLine(in: state, limits: limits) {
        case .winningLine(let line), .bestEffortLine(let line, _):
            golfPlan = GolfPlanner.keyedMoves(along: line, from: state)
            return plannedGolfHint(for: key, in: state)

        case .noProgress:
            // A proof, not a budget artifact: any clearable line registers
            // within the search's first ~two dozen expansions (a root play
            // pops immediately; otherwise only draws are legal, a chain of at
            // most 16, and a draw-enabled play pops right after its draw), so
            // no-progress is only ever reached by exhausting that region —
            // far under the interactive budget. Every remaining action is
            // provably futile stock-churning and silence is the honest
            // answer. The hint button re-enables after the player's next move.
            return nil
        }
    }

    func plannedGolfHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        // materialize re-validates the cached move against the live state.
        guard let move = golfPlan[key] else { return nil }
        return GolfPlanner.materialize(move, in: state)
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

    func spiderHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = SpiderPlanner.stateKey(for: state)
        if let hint = plannedSpiderHint(for: key, in: state) {
            return hint
        }

        spiderPlan.removeAll()
        let limits = SpiderPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.spiderSearchBudget)
        )
        switch SpiderPlanner.bestLine(in: state, limits: limits) {
        case .line(let line):
            spiderPlan = SpiderPlanner.keyedActions(along: line, from: state)
            return plannedSpiderHint(for: key, in: state)

        case .noProgress:
            // The searched region holds no tableau progress. Unlike Yukon,
            // Spider has a rescue the planner can vouch for: dealing the next
            // stock row is what a strong player does with a groomed-but-stuck
            // tableau. The preparation line fills any empty columns first (the
            // deal is illegal over them) and is cached whole — filling costs
            // score, so re-planning from an intermediate position would just
            // recommend undoing it.
            //
            // Deliberately falls back for truncated no-progress too, not just
            // exhaustive proof: a Spider midgame's improvement-free region
            // usually exceeds any budget, so most stuck verdicts are truncated,
            // and gating the deal on exhaustiveness measures 8 points worse at
            // 2-suit in the hint probe (deals withheld are games stalled).
            guard let preparation = SpiderPlanner.dealPreparationLine(in: state) else {
                return nil
            }
            spiderPlan = SpiderPlanner.keyedActions(along: preparation, from: state)
            return plannedSpiderHint(for: key, in: state)
        }
    }

    func fortyThievesHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = FortyThievesPlanner.stateKey(for: state)
        if let hint = plannedFortyThievesHint(for: key, in: state) {
            return hint
        }

        fortyThievesPlan.removeAll()
        let limits = FortyThievesPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.fortyThievesSearchBudget)
        )
        switch FortyThievesPlanner.bestLine(in: state, limits: limits) {
        case .line(let line):
            fortyThievesPlan = FortyThievesPlanner.keyedActions(along: line, from: state)
            return plannedFortyThievesHint(for: key, in: state)

        case .noProgress:
            // The searched region holds no improvement, so the way forward is
            // the next stock card — what a strong player does with a
            // groomed-but-stuck board. Deliberately offered for truncated
            // no-progress too, not just exhaustive proof (Spider's measured
            // lesson: hints withheld are games stalled), and deliberately not
            // cached: the fallback tap is one action, strictly monotone, and
            // the fresh waste top may unlock an improving line worth a fresh
            // search. Silence only when the stock is out too — then the shared
            // candidate scan in `anyPlayerMoveExists` is the exact loss test.
            guard !state.stock.isEmpty else { return nil }
            return .stockTap
        }
    }

    func plannedFortyThievesHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        // materialize re-validates the cached action against the live state.
        guard let action = fortyThievesPlan[key] else { return nil }
        return FortyThievesPlanner.materialize(action, in: state)
    }

    func canfieldHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = CanfieldPlanner.stateKey(for: state)
        if let hint = plannedCanfieldHint(for: key, in: state) {
            return hint
        }

        canfieldPlan.removeAll()
        let limits = CanfieldPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.canfieldSearchBudget)
        )
        switch CanfieldPlanner.bestLine(in: state, limits: limits) {
        case .line(let line):
            canfieldPlan = CanfieldPlanner.keyedActions(along: line, from: state)
            return plannedCanfieldHint(for: key, in: state)

        case .noProgress(let searchWasExhaustive):
            // An exhaustive search covered every reachable position — taps and
            // recycles included — so exhaustion is a proof the game is over;
            // a tap hint would just churn the dead stock in a circle, and
            // silence is the honest answer. Only a truncated no-progress falls
            // back to the tap (a large searched region held no improvement,
            // but the unexplored remainder may), mirroring Forty Thieves.
            guard !searchWasExhaustive else { return nil }
            guard !state.stock.isEmpty || !state.waste.isEmpty else { return nil }
            return .stockTap
        }
    }

    func plannedCanfieldHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        // materialize re-validates the cached action against the live state.
        guard let action = canfieldPlan[key] else { return nil }
        return CanfieldPlanner.materialize(action, in: state)
    }

    func plannedSpiderHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        switch spiderPlan[key] {
        case .move(let selection, let destination):
            guard AutoMoveAdvisor.selectionMatchesState(selection, in: state),
                  AutoMoveAdvisor.legalDestinations(for: selection, in: state)
                      .contains(destination) else {
                return nil
            }
            return .move(HintAdvisor.HintMove(selection: selection, destination: destination))
        case .stockDeal:
            guard SpiderGameRules.canDealFromStock(state: state) else { return nil }
            return .stockTap
        case .none:
            return nil
        }
    }

    func scorpionHint(in state: GameState) -> HintAdvisor.Hint? {
        let key = ScorpionPlanner.stateKey(for: state)
        if let hint = plannedScorpionHint(for: key, in: state) {
            return hint
        }

        scorpionPlan.removeAll()
        let limits = ScorpionPlanner.Limits(
            deadline: Date().addingTimeInterval(Self.scorpionSearchBudget)
        )
        switch ScorpionPlanner.bestLine(in: state, limits: limits) {
        case .line(let line):
            scorpionPlan = ScorpionPlanner.keyedActions(along: line, from: state)
            return plannedScorpionHint(for: key, in: state)

        case .noProgress:
            // The searched region holds no tableau progress. Like Spider,
            // Scorpion has a rescue the planner can vouch for: the deal is what
            // a strong player does with a stuck tableau, and unlike Spider's it
            // is legal at any time, so no preparation line is needed. Falls
            // back for truncated no-progress too, mirroring Spider's measured
            // rationale — most stuck verdicts are truncated, and a withheld
            // deal is a stalled game. With the stock spent, silence is the
            // honest answer.
            guard ScorpionGameRules.canDealFromStock(state: state) else { return nil }
            scorpionPlan = ScorpionPlanner.keyedActions(along: [.stockDeal], from: state)
            return plannedScorpionHint(for: key, in: state)
        }
    }

    func plannedScorpionHint(for key: String, in state: GameState) -> HintAdvisor.Hint? {
        switch scorpionPlan[key] {
        case .move(let selection, let destination):
            guard AutoMoveAdvisor.selectionMatchesState(selection, in: state),
                  AutoMoveAdvisor.legalDestinations(for: selection, in: state)
                      .contains(destination) else {
                return nil
            }
            return .move(HintAdvisor.HintMove(selection: selection, destination: destination))
        case .stockDeal:
            guard ScorpionGameRules.canDealFromStock(state: state) else { return nil }
            return .stockTap
        case .none:
            return nil
        }
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
