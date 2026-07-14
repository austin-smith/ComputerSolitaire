import Foundation

/// Exact solver behind Golf hints.
///
/// Golf's exact state is tiny: how deep each of the seven columns still is,
/// how many stock cards were drawn, and the waste's top rank (the only waste
/// fact that gates legality — buried waste history and suits are
/// strategically inert, so merging them is exact state merging, not a
/// collision). Columns only ever shrink from the exposed end and draws are
/// strictly sequential, so depths determine exactly which cards remain, and
/// the position packs into one collision-free 30-bit code (see `Board`).
/// Every move consumes a card (plays shrink the board, draws shrink the
/// stock), so the game graph is a DAG of depth ≤ 51 — but its seven
/// independent columns reach far more positions per deal than TriPeaks'
/// covering DAG, which is why the node budget is larger and the search nodes
/// are packed to twelve bytes (see `Limits` and `Node`).
///
/// The search is the same single depth-first pass as `TriPeaksPlanner`, plays
/// explored before draws — no heuristic, no pruning. Strict Golf legality
/// (one rank up or down, no wraparound, nothing plays on a King) lives in
/// `GolfGameRules.canPlayRank`, which the move generator calls directly, so
/// the rules and the solver cannot drift. Because nothing is pruned, one
/// exhausted pass is simultaneously a proof the deal cannot be won and the
/// exact max-clear answer, so unwinnable deals (the majority under strict
/// rules) still get the best continuation found. Silence is reserved for
/// positions where not one more column card is clearable.
///
/// Hint-quality baselines live in the `tools/hint-probe` ledger; the measured
/// verdict split is recorded below `Limits`.
nonisolated enum GolfPlanner {
    struct Limits {
        var maxNodes: Int
        var deadline: Date?

        // Golf's seven independent columns reach far more positions per deal
        // than TriPeaks' covering DAG, so the budget is sized to decide deals,
        // not just to bound pathology: measured over 10,000 seeded
        // release-build deals, this cap proves 26.1% winnable, 66.3%
        // unwinnable, and leaves 7.6% undecided (a 200k cap left 61%
        // undecided), at a median `bestLine` of 36ms with ~40 MB of transient
        // search state on the hardest deals. It stays affordable because a
        // search node packs into 12 bytes (the whole board is a 30-bit code —
        // see `Board` and `Node`). No maxDepth: the game graph is a DAG whose
        // depth is structurally bounded (≤ 35 plays + 16 draws).
        init(maxNodes: Int = 1_000_000, deadline: Date? = nil) {
            self.maxNodes = maxNodes
            self.deadline = deadline
        }
    }

    enum Move: Equatable {
        /// Play the exposed card of `column` onto the waste, making it the new
        /// match target.
        case play(column: Int)
        /// Flip the next stock card onto the waste (single pass, no redeals).
        case draw
    }

    enum SearchOutcome {
        /// Replaying this line clears the columns; the deal is won.
        case winningLine([Move])
        /// No winning line exists (or fit the budget); this line clears the most
        /// column cards found. The flag is a proof when the unpruned graph was
        /// exhausted rather than the budget running out.
        case bestEffortLine([Move], dealIsProvedUnwinnable: Bool)
        /// Not even one more column card is clearable within the horizon.
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
        guard state.variant == .golf, let position = Position(state: state) else {
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
    /// top card: suits and buried waste history never matter in Golf, so
    /// positions with identical hint futures intentionally share a key.
    static func stateKey(for state: GameState) -> String {
        var key = String()
        key.reserveCapacity(64)
        func append(card: Card) {
            key.append(String(UnicodeScalar(UInt8(96 + card.rank.rawValue))))
        }
        for column in state.tableau {
            for card in column { append(card: card) }
            key.append("|")
        }
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
            return GolfGameRules.stateByApplying(
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
            return nextState
        }
    }
}

// MARK: - Session move mapping

nonisolated private extension GolfPlanner {
    static func sessionMove(
        for move: Move,
        in state: GameState
    ) -> (selection: Selection, destination: Destination)? {
        guard case .play(let column) = move else { return nil }
        guard state.tableau.indices.contains(column),
              let card = state.tableau[column].last else {
            return nil
        }
        return (
            Selection(
                source: .tableau(pile: column, index: state.tableau[column].count - 1),
                cards: [card]
            ),
            .waste
        )
    }
}

// MARK: - Compact position

nonisolated private extension GolfPlanner {
    /// The deal's immutable rank tables plus the packed dynamic board. Stock cards
    /// are indexed in draw order relative to the root; cards already in the waste
    /// below its top are simply absent — the search never needs them.
    struct Position {
        /// Rank per column card, bottom to top, as dealt at the root. Columns
        /// only shrink from the exposed (last) end, so a board depth indexes a
        /// prefix of each column.
        let columnRanks: [[Int]]
        /// Rank per undrawn stock card, in draw order (index 0 draws next).
        let stockRanks: [Int]
        let root: Board

        init?(state: GameState) {
            guard state.tableau.count == GolfGameRules.columnCount else { return nil }
            guard state.tableau.allSatisfy({ $0.count <= GolfGameRules.columnDepth }) else {
                return nil
            }
            guard state.stock.count <= GolfGameRules.dealStockCardCount else { return nil }
            // The deal starts the waste with one card and nothing ever leaves
            // it, so an empty waste marks a malformed state.
            guard let wasteTop = state.waste.last else { return nil }

            columnRanks = state.tableau.map { column in column.map(\.rank.rawValue) }
            stockRanks = state.stock.reversed().map(\.rank.rawValue)
            root = Board(
                columnDepths: state.tableau.map(\.count),
                drawsUsed: 0,
                wasteTopRank: wasteTop.rank.rawValue
            )
        }
    }

    /// One Golf position in 30 bits: the seven column depths (3 bits each,
    /// 0–5), draws made since the root (5 bits, ≤ 16), and the waste's top
    /// rank (4 bits, 1–13). Columns only shrink from the exposed end and
    /// draws are strictly sequential, so depths determine exactly which cards
    /// remain; the waste top is the one fact depths and draws cannot
    /// reconstruct (it records whether the last event was a play or a draw).
    /// Together the three fields determine the position's entire future —
    /// making `code` an exact, collision-free transposition key that round-
    /// trips losslessly (which is what lets search nodes store the code alone).
    struct Board: Equatable {
        /// Packed 3-bit depths, column 0 in the lowest bits.
        var packedDepths: UInt32
        var drawsUsed: Int
        var wasteTopRank: Int

        init(columnDepths: [Int], drawsUsed: Int, wasteTopRank: Int) {
            var packed: UInt32 = 0
            for (column, depth) in columnDepths.enumerated() {
                packed |= UInt32(depth) << (3 * UInt32(column))
            }
            packedDepths = packed
            self.drawsUsed = drawsUsed
            self.wasteTopRank = wasteTopRank
        }

        init(code: UInt32) {
            packedDepths = code & 0x1F_FFFF
            drawsUsed = Int((code >> 21) & 0b11111)
            wasteTopRank = Int((code >> 26) & 0b1111)
        }

        var code: UInt32 {
            packedDepths
                | (UInt32(drawsUsed) << 21)
                | (UInt32(wasteTopRank) << 26)
        }

        var remainingCount: Int {
            (0..<GolfGameRules.columnCount).reduce(0) { $0 + depth(of: $1) }
        }

        func depth(of column: Int) -> Int {
            Int((packedDepths >> (3 * UInt32(column))) & 0b111)
        }

        mutating func removeExposedCard(from column: Int) {
            packedDepths -= 1 << (3 * UInt32(column))
        }
    }
}

// MARK: - Move generation and transitions

nonisolated private extension GolfPlanner {
    /// Legal moves in a fixed, deterministic order: playable columns ascending,
    /// then draw — so equal-depth ties favor clearing over flipping and lines
    /// read sensibly. Legality is `GolfGameRules.canPlayRank`, so the strict
    /// no-wraparound and dead-King rules hold here by construction: a waste-top
    /// King generates no plays, leaving the draw as the only move.
    static func moves(from board: Board, position: Position) -> [Move] {
        var moves: [Move] = []

        for column in 0..<GolfGameRules.columnCount {
            let depth = board.depth(of: column)
            guard depth > 0,
                  GolfGameRules.canPlayRank(
                      position.columnRanks[column][depth - 1],
                      ontoWasteTop: board.wasteTopRank
                  ) else { continue }
            moves.append(.play(column: column))
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
        case .play(let column):
            next.wasteTopRank = position.columnRanks[column][board.depth(of: column) - 1]
            next.removeExposedCard(from: column)
        case .draw:
            next.wasteTopRank = position.stockRanks[next.drawsUsed]
            next.drawsUsed += 1
        }
        return next
    }
}

// MARK: - Search

nonisolated private extension GolfPlanner {
    /// One explored position, packed to 12 bytes so the million-node budget
    /// costs ~12 MB of nodes instead of ~50: the 30-bit board code stands in
    /// for the whole board (it round-trips through `Board(code:)`), the move
    /// that reached it packs into a byte, and depth fits sixteen bits (≤ 51).
    struct Node {
        let code: UInt32
        let parent: Int32
        let move: UInt8
        let depth: UInt16

        static let noMove = UInt8.max
        static let drawMove = UInt8(GolfGameRules.columnCount)

        static func encode(_ move: Move) -> UInt8 {
            switch move {
            case .play(let column):
                return UInt8(column)
            case .draw:
                return drawMove
            }
        }

        var decodedMove: Move? {
            switch move {
            case Self.noMove:
                return nil
            case Self.drawMove:
                return .draw
            default:
                return .play(column: Int(move))
            }
        }
    }

    /// One depth-first pass over the transposition-deduplicated game graph.
    /// Children push in reverse generation order so the dive pops plays
    /// (lowest column first) before the draw — the search plays whenever it
    /// can and flips only when a branch is spent. Because nothing is pruned,
    /// draining the stack proves unwinnability and makes the best-effort line
    /// the exact max-clear answer (ties prefer the shallower line).
    static func search(
        from position: Position,
        limits: Limits
    ) -> (winLine: [Move]?, bestLine: [Move]?, exhaustive: Bool) {
        if position.root.packedDepths == 0 {
            return (winLine: [], bestLine: nil, exhaustive: true)
        }

        var nodes: [Node] = [
            Node(code: position.root.code, parent: -1, move: Node.noMove, depth: 0)
        ]
        var visited: Set<UInt32> = [position.root.code]
        var pending: [Int32] = [0]
        var expansions = 0
        var wasTruncated = false
        var best: (index: Int32, remaining: Int, depth: UInt16)?

        while let nodeIndex = pending.popLast() {
            let node = nodes[Int(nodeIndex)]
            let board = Board(code: node.code)
            let remaining = board.remainingCount

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

            for move in moves(from: board, position: position).reversed() {
                let nextBoard = apply(move, to: board, position: position)
                guard visited.insert(nextBoard.code).inserted else { continue }
                nodes.append(
                    Node(
                        code: nextBoard.code,
                        parent: nodeIndex,
                        move: Node.encode(move),
                        depth: node.depth + 1
                    )
                )
                pending.append(Int32(nodes.count - 1))
            }
        }

        guard let best, let moves = line(to: best.index, nodes: nodes) else {
            return (winLine: nil, bestLine: nil, exhaustive: !wasTruncated)
        }
        return (winLine: nil, bestLine: moves, exhaustive: !wasTruncated)
    }

    static func line(to index: Int32, nodes: [Node]) -> [Move]? {
        var moves: [Move] = []
        var current = index
        while current > 0 {
            let node = nodes[Int(current)]
            guard let move = node.decodedMove else { return nil }
            moves.append(move)
            current = node.parent
        }
        return moves.reversed()
    }
}
