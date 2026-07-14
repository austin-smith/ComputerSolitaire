import Foundation

/// Exact solver behind TriPeaks hints.
///
/// TriPeaks has the tiniest exact state of any variant: which peak slots remain,
/// how many stock cards were drawn, and the waste's top rank (the only waste fact
/// that gates legality — buried waste history and suits are strategically inert,
/// so merging them is exact state merging, not a collision). That position packs
/// into one collision-free 37-bit code (see `Board`). Every move consumes a card
/// (plays shrink the board, draws shrink the stock), so the game graph is a DAG
/// of depth ≤ 51 with small branching, and reachable spaces per deal are small
/// enough to exhaust outright.
///
/// The search is a single depth-first pass with plays explored before draws —
/// no heuristic, no `BinaryHeap`, no pruning. Reachable spaces run to millions
/// of positions, so frontier order is the whole ballgame: breadth-first (and
/// even draw-bucketed) orders must sweep the graph's width before reaching
/// depth-45 wins and blow any budget, while the plays-first dive reaches a win
/// in near-linear time on most winnable deals and backtracks through the
/// transposition set otherwise. The dive's preference for playing over flipping
/// at every step is also what makes its lines read naturally (long chains, no
/// idle draws); strictly draw-minimal wins were measured and rejected — they
/// force near-exhaustive sweeps of every low-draw region first. Because nothing
/// is pruned, one exhausted pass is simultaneously a proof the deal cannot be
/// won and the exact max-clear answer, so unwinnable deals (the solver plays
/// the actual deal, reading face-down ranks like every planner in this app —
/// hints are verified lines, not guesses) still get the best continuation
/// found. Silence is reserved for positions where not one more peak card is
/// clearable. If unwinnability proofs ever need to land inside the interactive
/// budget, the ready lever is the exact rank-connectivity prune (a remaining
/// card with no wrap-adjacent rank anywhere in the waste top + remaining stock
/// + remaining peaks can never be played), which must then be confined to a
/// separate win search to keep max-clear exact.
///
/// Measured at the default budget over 10,000 seeded release-build deals:
/// 95.6% proved winnable, 0.2% proved unwinnable, 4.1% undecided at budget
/// (hard deals whose reachable graphs exceed 200k nodes; they still get
/// best-effort lines); `bestLine` median 0.07ms. Hint-quality baselines live
/// in the `tools/hint-probe` ledger: 95.4% of 500 deals won by following every
/// hint against a 0.0% random-control floor, zero loops.
nonisolated enum TriPeaksPlanner {
    struct Limits {
        var maxNodes: Int
        var deadline: Date?

        // Expansions are bit operations on a packed board, and reachable spaces
        // per deal run well under this cap, so the budget exists for pathological
        // deals rather than typical ones. No maxDepth: the game graph is a DAG
        // whose depth is structurally bounded (≤ 28 plays + 23 draws).
        init(maxNodes: Int = 200_000, deadline: Date? = nil) {
            self.maxNodes = maxNodes
            self.deadline = deadline
        }
    }

    enum Move: Equatable {
        /// Play the uncovered card at `slot` onto the waste, making it the new
        /// match target.
        case play(slot: Int)
        /// Flip the next stock card onto the waste (single pass, no redeals).
        case draw
    }

    enum SearchOutcome {
        /// Replaying this line clears the peaks; the deal is won.
        case winningLine([Move])
        /// No winning line exists (or fit the budget); this line clears the most
        /// peak cards found. The flag is a proof when the unpruned graph was
        /// exhausted rather than the budget running out.
        case bestEffortLine([Move], dealIsProvedUnwinnable: Bool)
        /// Not even one more peak card is clearable within the horizon.
        /// Exhaustive means proof (the full move graph was emptied).
        case noProgress(searchWasExhaustive: Bool)
    }

    static func bestHint(in state: GameState, limits: Limits = Limits()) -> HintAdvisor.Hint? {
        let line: [Move]
        switch bestLine(in: state, limits: limits) {
        case .winningLine(let moves):
            line = moves
        case .bestEffortLine(let moves, _):
            line = moves
        case .noProgress:
            return nil
        }
        guard let move = line.first else { return nil }
        return materialize(move, in: state)
    }

    static func bestLine(in state: GameState, limits: Limits = Limits()) -> SearchOutcome {
        guard state.variant == .tripeaks, let position = Position(state: state) else {
            return .noProgress(searchWasExhaustive: false)
        }

        let result = search(from: position, limits: limits)
        if let line = result.winLine {
            return .winningLine(line)
        }
        guard let line = result.bestLine else {
            return .noProgress(searchWasExhaustive: result.exhaustive)
        }
        return .bestEffortLine(line, dealIsProvedUnwinnable: result.exhaustive)
    }

    /// Exact position key, stable across `Card` identities; used to look up the
    /// cached line as the player follows it. Ranks only, and only the waste's
    /// top card: suits and buried waste history never matter in TriPeaks, so
    /// positions with identical hint futures intentionally share a key.
    static func stateKey(for state: GameState) -> String {
        var key = String()
        key.reserveCapacity(64)
        func append(card: Card) {
            key.append(String(UnicodeScalar(UInt8(96 + card.rank.rawValue))))
        }
        for slot in state.triPeaks {
            if let card = slot {
                append(card: card)
            } else {
                key.append("-")
            }
        }
        key.append("|")
        for card in state.stock { append(card: card) }
        key.append("|")
        if let wasteTop = state.waste.last {
            append(card: wasteTop)
        }
        return key
    }

    /// Maps each position along the line to the move to play there, so consecutive
    /// hints are instant while the player follows (or plays ahead along) the line.
    static func keyedMoves(along line: [Move], from state: GameState) -> [String: Move] {
        var keyed: [String: Move] = [:]
        var current = state
        for move in line {
            keyed[stateKey(for: current)] = move
            guard let next = apply(move, to: current) else { break }
            current = next
        }
        return keyed
    }

    /// Converts a planner move into the executable hint, re-validating against the
    /// live state so a stale cached move can never surface.
    static func materialize(_ move: Move, in state: GameState) -> HintAdvisor.Hint? {
        switch move {
        case .play:
            guard let (selection, destination) = sessionMove(for: move, in: state),
                  AutoMoveAdvisor.selectionMatchesState(selection, in: state),
                  AutoMoveAdvisor.legalDestinations(for: selection, in: state)
                      .contains(destination) else {
                return nil
            }
            return .move(HintAdvisor.HintMove(selection: selection, destination: destination))
        case .draw:
            guard !state.stock.isEmpty else { return nil }
            return .stockTap
        }
    }

    /// Applies a planner move to a real game state, mirroring the session's move
    /// effects; used to walk `keyedMoves` and to replay lines in tests.
    static func apply(_ move: Move, to state: GameState) -> GameState? {
        switch move {
        case .play:
            guard let (selection, destination) = sessionMove(for: move, in: state) else { return nil }
            return TriPeaksGameRules.stateByApplying(
                selection: selection,
                destination: destination,
                to: state
            )
        case .draw:
            guard !state.stock.isEmpty else { return nil }
            var nextState = state
            var card = nextState.stock.removeLast()
            card.isFaceUp = true
            nextState.waste.append(card)
            nextState.wasteDrawCount = 1
            // A stock flip breaks the scoring chain, exactly as the session's
            // draw path does.
            nextState.triPeaksChainLength = 0
            return nextState
        }
    }
}

// MARK: - Session move mapping

nonisolated private extension TriPeaksPlanner {
    static func sessionMove(
        for move: Move,
        in state: GameState
    ) -> (selection: Selection, destination: Destination)? {
        guard case .play(let slot) = move else { return nil }
        guard state.triPeaks.indices.contains(slot), let card = state.triPeaks[slot] else {
            return nil
        }
        return (Selection(source: .triPeaks(index: slot), cards: [card]), .waste)
    }
}

// MARK: - Compact position

nonisolated private extension TriPeaksPlanner {
    /// The deal's immutable rank tables plus the packed dynamic board. Stock cards
    /// are indexed in draw order relative to the root; cards already in the waste
    /// below its top are simply absent — the search never needs them.
    struct Position {
        /// Rank per peak slot (face-down ranks included — the solver plays the
        /// actual deal); 0 for slots already cleared at the root.
        let slotRanks: [Int]
        /// Rank per undrawn stock card, in draw order (index 0 draws next).
        let stockRanks: [Int]
        let root: Board

        init?(state: GameState) {
            guard state.triPeaks.count == TriPeaksGeometry.cardCount else { return nil }
            guard state.stock.count <= Board.maxStockCount else { return nil }
            // The deal starts the waste with one card and nothing ever leaves
            // it, so an empty waste marks a malformed state.
            guard let wasteTop = state.waste.last else { return nil }

            slotRanks = state.triPeaks.map { $0?.rank.rawValue ?? 0 }
            stockRanks = state.stock.reversed().map(\.rank.rawValue)

            var tableauMask: UInt32 = 0
            for index in state.triPeaks.indices where state.triPeaks[index] != nil {
                tableauMask |= 1 << UInt32(index)
            }
            root = Board(
                tableauMask: tableauMask,
                drawsUsed: 0,
                wasteTopRank: wasteTop.rank.rawValue
            )
        }
    }

    /// One TriPeaks position in 37 bits: which peak slots hold cards (28), draws
    /// made since the root (5 bits, ≤ 23), and the waste's top rank (4 bits,
    /// 1–13). Draws are strictly sequential and nothing ever leaves the waste, so
    /// these three fields determine the position's entire future — making `code`
    /// an exact, collision-free transposition key.
    struct Board: Equatable {
        static let maxStockCount = 31

        var tableauMask: UInt32
        var drawsUsed: Int
        var wasteTopRank: Int

        var code: UInt64 {
            UInt64(tableauMask)
                | (UInt64(drawsUsed) << 28)
                | (UInt64(wasteTopRank) << 33)
        }

        var remainingCount: Int {
            tableauMask.nonzeroBitCount
        }

        func holdsCard(at slot: Int) -> Bool {
            tableauMask & (1 << UInt32(slot)) != 0
        }

        func isUncovered(_ slot: Int) -> Bool {
            TriPeaksPlanner.coveringMasks[slot] & tableauMask == 0
        }
    }

    /// Bits of the two slots covering each slot; 0 for the base row.
    static let coveringMasks: [UInt32] = (0..<TriPeaksGeometry.cardCount).map { index in
        guard let covering = TriPeaksGeometry.coveringIndices(of: index) else { return 0 }
        return (1 << UInt32(covering.left)) | (1 << UInt32(covering.right))
    }
}

// MARK: - Move generation and transitions

nonisolated private extension TriPeaksPlanner {
    /// One rank above or below with wrap, mirroring
    /// `TriPeaksGameRules.ranksAdjacentWithWrap` on raw rank values.
    static func ranksAreAdjacent(_ first: Int, _ second: Int) -> Bool {
        let difference = abs(first - second)
        return difference == 1 || difference == Rank.allCases.count - 1
    }

    /// Legal moves in a fixed, deterministic order: playable slots ascending,
    /// then draw — so equal-depth ties favor clearing over flipping and lines
    /// read sensibly.
    static func moves(from board: Board, position: Position) -> [Move] {
        var moves: [Move] = []

        for slot in 0..<TriPeaksGeometry.cardCount
        where board.holdsCard(at: slot)
            && board.isUncovered(slot)
            && ranksAreAdjacent(position.slotRanks[slot], board.wasteTopRank) {
            moves.append(.play(slot: slot))
        }

        if board.drawsUsed < position.stockRanks.count {
            moves.append(.draw)
        }

        return moves
    }

    /// Applies a generated move without re-validating legality (the search only
    /// feeds in moves it just generated).
    static func apply(_ move: Move, to board: Board, position: Position) -> Board {
        var next = board
        switch move {
        case .play(let slot):
            next.tableauMask &= ~(1 << UInt32(slot))
            next.wasteTopRank = position.slotRanks[slot]
        case .draw:
            next.wasteTopRank = position.stockRanks[next.drawsUsed]
            next.drawsUsed += 1
        }
        return next
    }
}

// MARK: - Search

nonisolated private extension TriPeaksPlanner {
    struct Node {
        let board: Board
        let parent: Int
        let move: Move?
        let depth: Int
    }

    /// One depth-first pass over the transposition-deduplicated game graph.
    /// Children push in reverse generation order so the dive pops plays
    /// (lowest slot first) before the draw — the search plays whenever it can
    /// and flips only when a branch is spent. Because nothing is pruned,
    /// draining the stack proves unwinnability and makes the best-effort line
    /// the exact max-clear answer (ties prefer the shallower line).
    static func search(
        from position: Position,
        limits: Limits
    ) -> (winLine: [Move]?, bestLine: [Move]?, exhaustive: Bool) {
        if position.root.tableauMask == 0 {
            return (winLine: [], bestLine: nil, exhaustive: true)
        }

        var nodes: [Node] = [Node(board: position.root, parent: -1, move: nil, depth: 0)]
        var visited: Set<UInt64> = [position.root.code]
        var pending: [Int] = [0]
        var expansions = 0
        var wasTruncated = false
        var best: (index: Int, remaining: Int, depth: Int)?

        while let nodeIndex = pending.popLast() {
            let node = nodes[nodeIndex]
            let remaining = node.board.remainingCount

            if remaining == 0 {
                return (
                    winLine: line(to: nodeIndex, nodes: nodes),
                    bestLine: nil,
                    exhaustive: false
                )
            }
            let improvesBest = best.map {
                remaining < $0.remaining || (remaining == $0.remaining && node.depth < $0.depth)
            } ?? (remaining < position.root.remainingCount)
            if improvesBest {
                best = (nodeIndex, remaining, node.depth)
            }

            expansions += 1
            if nodes.count >= limits.maxNodes {
                wasTruncated = true
                break
            }
            if expansions % 64 == 0, let deadline = limits.deadline, Date() > deadline {
                wasTruncated = true
                break
            }

            for move in moves(from: node.board, position: position).reversed() {
                let nextBoard = apply(move, to: node.board, position: position)
                guard visited.insert(nextBoard.code).inserted else { continue }
                nodes.append(
                    Node(board: nextBoard, parent: nodeIndex, move: move, depth: node.depth + 1)
                )
                pending.append(nodes.count - 1)
            }
        }

        guard let best, let moves = line(to: best.index, nodes: nodes) else {
            return (winLine: nil, bestLine: nil, exhaustive: !wasTruncated)
        }
        return (winLine: nil, bestLine: moves, exhaustive: !wasTruncated)
    }

    static func line(to index: Int, nodes: [Node]) -> [Move]? {
        var moves: [Move] = []
        var current = index
        while current > 0 {
            let node = nodes[current]
            guard let move = node.move else { return nil }
            moves.append(move)
            current = node.parent
        }
        return moves.reversed()
    }
}
