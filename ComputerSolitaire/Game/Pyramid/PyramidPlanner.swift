import Foundation

/// Exact two-stage solver behind Pyramid hints.
///
/// Pyramid is a perfect-information game with a tiny exact state: which pyramid
/// slots remain, which stock cards were consumed by pairing, how far the current
/// pass has drawn, and how many recycles are spent. That position packs into one
/// collision-free 59-bit code (see `Board`), so the transposition table stores
/// exact keys — no hashing judgment calls — and the game graph is a DAG (removals
/// shrink masks, draws advance the cut, resets spend a bounded counter), so depth
/// is structurally bounded and followed lines can never revisit a position.
///
/// Stage one runs weighted A* for a full winning line (`f = g + 10·h` with an
/// admissible `h`, so misses are budget misses, not blind spots), pruning
/// positions the partner-count check proves unwinnable; emptying that pruned
/// graph is a proof the deal cannot be won. Unlike the other variants, lost deals
/// are common under the three-pass rule, so stage two then finds the line
/// clearing the most pyramid cards and hints follow it — silence is reserved for
/// positions where not one more pyramid card is clearable, where any nudge would
/// be provably futile stock-churning.
///
/// Measured at the default budget over 10,000 seeded release-build deals:
/// 79.5% proved winnable, 0.8% proved unwinnable, 19.8% undecided at budget
/// (hard deals whose reachable graphs exceed 150k nodes; they still get
/// best-effort lines); `bestLine` median 0.5ms. Hint-quality baselines live in
/// the `tools/hint-probe` ledger: 80.2% of 500 deals won by following every
/// hint against a 15.2% random-control floor, zero loops.
nonisolated enum PyramidPlanner {
    struct Limits {
        var maxNodes: Int
        var deadline: Date?

        // Expansions are bit operations on a packed board, and reachable spaces
        // per deal run well under this cap, so the budget exists for pathological
        // deals rather than typical ones. No maxDepth: the game graph is a DAG
        // whose depth is structurally bounded (≤ 16 removals + 72 draws + 2 resets).
        init(maxNodes: Int = 150_000, deadline: Date? = nil) {
            self.maxNodes = maxNodes
            self.deadline = deadline
        }
    }

    enum PairTarget: Equatable {
        case pyramid(slot: Int)
        case wasteTop
    }

    enum Move: Equatable {
        /// Canonical order: pyramid slots ascending; `.wasteTop` second.
        case removePair(PairTarget, PairTarget)
        case removeKing(PairTarget)
        case draw
        case resetStock
    }

    enum SearchOutcome {
        /// Replaying this line clears the pyramid; the deal is won.
        case winningLine([Move])
        /// No winning line exists (or fit the budget); this line clears the most
        /// pyramid cards found. The flag is a proof when stage one exhausted its
        /// pruned graph rather than running out of budget.
        case bestEffortLine([Move], dealIsProvedUnwinnable: Bool)
        /// Not even one more pyramid card is clearable within the horizon.
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
        guard state.variant == .pyramid, let position = Position(state: state) else {
            return .noProgress(searchWasExhaustive: false)
        }

        let win = winSearch(from: position, limits: limits)
        if let line = win.line {
            return .winningLine(line)
        }

        let clear = maxClearSearch(from: position, limits: limits)
        guard let line = clear.line else {
            return .noProgress(searchWasExhaustive: clear.exhaustive)
        }
        if clear.bestRemaining == 0 {
            // Stage one ran out of budget before reaching this win.
            return .winningLine(line)
        }
        return .bestEffortLine(line, dealIsProvedUnwinnable: win.exhaustive)
    }

    /// Exact position key, stable across `Card` identities; used to look up the
    /// cached line as the player follows it. Ranks only: suits never matter in
    /// Pyramid, so suit-equivalent positions intentionally share a key.
    static func stateKey(for state: GameState) -> String {
        var key = String()
        key.reserveCapacity(64)
        func append(card: Card) {
            key.append(String(UnicodeScalar(UInt8(96 + card.rank.rawValue))))
        }
        for slot in state.pyramid {
            if let card = slot {
                append(card: card)
            } else {
                key.append("-")
            }
        }
        key.append("|")
        for card in state.stock { append(card: card) }
        key.append("|")
        for card in state.waste { append(card: card) }
        key.append("|")
        key.append(String(state.wasteRecyclesUsed))
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
        case .removePair, .removeKing:
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
        case .resetStock:
            guard PyramidGameRules.canRecycleWaste(in: state) else { return nil }
            return .stockTap
        }
    }

    /// Applies a planner move to a real game state, mirroring the session's move
    /// effects; used to walk `keyedMoves` and to replay lines in tests.
    static func apply(_ move: Move, to state: GameState) -> GameState? {
        switch move {
        case .removePair, .removeKing:
            guard let (selection, destination) = sessionMove(for: move, in: state) else { return nil }
            return PyramidGameRules.stateByApplying(
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
        case .resetStock:
            guard PyramidGameRules.canRecycleWaste(in: state) else { return nil }
            var nextState = state
            nextState.stock = nextState.waste.reversed().map { card in
                var recycledCard = card
                recycledCard.isFaceUp = false
                return recycledCard
            }
            nextState.waste.removeAll()
            nextState.wasteDrawCount = 0
            nextState.wasteRecyclesUsed += 1
            return nextState
        }
    }
}

// MARK: - Session move mapping

nonisolated private extension PyramidPlanner {
    static func sessionMove(
        for move: Move,
        in state: GameState
    ) -> (selection: Selection, destination: Destination)? {
        switch move {
        case .removePair(.pyramid(let first), .pyramid(let second)):
            guard let card = pyramidCard(at: first, in: state) else { return nil }
            return (Selection(source: .pyramid(index: first), cards: [card]), .pyramid(second))
        case .removePair(.pyramid(let slot), .wasteTop),
             .removePair(.wasteTop, .pyramid(let slot)):
            guard let card = pyramidCard(at: slot, in: state) else { return nil }
            return (Selection(source: .pyramid(index: slot), cards: [card]), .waste)
        case .removeKing(.pyramid(let slot)):
            guard let card = pyramidCard(at: slot, in: state) else { return nil }
            return (Selection(source: .pyramid(index: slot), cards: [card]), .discard)
        case .removeKing(.wasteTop):
            guard let card = state.waste.last else { return nil }
            return (Selection(source: .waste, cards: [card]), .discard)
        case .removePair(.wasteTop, .wasteTop), .draw, .resetStock:
            return nil
        }
    }

    static func pyramidCard(at slot: Int, in state: GameState) -> Card? {
        guard state.pyramid.indices.contains(slot) else { return nil }
        return state.pyramid[slot]
    }
}

// MARK: - Compact position

nonisolated private extension PyramidPlanner {
    /// The deal's immutable rank tables plus the packed dynamic board. Stock cards
    /// are indexed in draw order: the root's waste bottom-to-top (already drawn),
    /// then the remaining stock in draw order. Cards already discarded at the root
    /// are simply absent — the search never needs them.
    struct Position {
        /// Rank per pyramid slot; 0 for slots already empty at the root.
        let slotRanks: [Int]
        /// Rank per stock index, in draw order.
        let stockRanks: [Int]
        let root: Board

        init?(state: GameState) {
            guard state.pyramid.count == PyramidGeometry.cardCount else { return nil }
            guard state.stock.count + state.waste.count <= Board.maxStockCount else { return nil }
            guard (0...PyramidGameRules.maxWasteRecycles).contains(state.wasteRecyclesUsed) else {
                return nil
            }

            slotRanks = state.pyramid.map { $0?.rank.rawValue ?? 0 }
            // Draw order: waste bottom→top was drawn first; the next draw is the
            // stock's last element.
            stockRanks = state.waste.map(\.rank.rawValue)
                + state.stock.reversed().map(\.rank.rawValue)

            var pyramidMask: UInt32 = 0
            for index in state.pyramid.indices where state.pyramid[index] != nil {
                pyramidMask |= 1 << UInt32(index)
            }
            root = Board(
                pyramidMask: pyramidMask,
                stockRemovedMask: 0,
                cut: state.waste.count,
                passes: state.wasteRecyclesUsed
            )
        }
    }

    /// One Pyramid position in 59 bits: which pyramid slots hold cards, which
    /// stock cards were consumed by pairing, the draw cut (stock indices below it
    /// have been drawn this pass), and recycles spent. The waste needs no storage:
    /// it is a stack with top-only pops, so its contents are exactly the
    /// non-removed indices below the cut, in index order — making `code` an exact,
    /// collision-free transposition key.
    struct Board: Equatable {
        static let maxStockCount = 24

        var pyramidMask: UInt32
        var stockRemovedMask: UInt32
        var cut: Int
        var passes: Int

        var code: UInt64 {
            UInt64(pyramidMask)
                | (UInt64(stockRemovedMask) << 28)
                | (UInt64(cut) << 52)
                | (UInt64(passes) << 57)
        }

        var remainingCount: Int {
            pyramidMask.nonzeroBitCount
        }

        /// The top of the waste; cut normalization keeps this exactly `cut - 1`.
        var wasteTopIndex: Int? {
            cut > 0 ? cut - 1 : nil
        }

        func isRemoved(_ stockIndex: Int) -> Bool {
            stockRemovedMask & (1 << UInt32(stockIndex)) != 0
        }

        func nextDrawIndex(stockCount: Int) -> Int? {
            var index = cut
            while index < stockCount {
                if !isRemoved(index) { return index }
                index += 1
            }
            return nil
        }

        func canResetStock(stockCount: Int) -> Bool {
            passes < PyramidGameRules.maxWasteRecycles
                && cut > 0
                && nextDrawIndex(stockCount: stockCount) == nil
        }

        func isExposed(_ slot: Int) -> Bool {
            PyramidPlanner.childrenMasks[slot] & pyramidMask == 0
        }

        func holdsCard(at slot: Int) -> Bool {
            pyramidMask & (1 << UInt32(slot)) != 0
        }

        /// Removed indices at the cut boundary belong to neither pile, so cuts
        /// differing only across them are the same position; normalizing keeps the
        /// transposition key canonical and the waste top at `cut - 1`.
        mutating func normalizeCut() {
            while cut > 0, isRemoved(cut - 1) {
                cut -= 1
            }
        }
    }

    /// Bits of the two slots covering each slot; 0 for the bottom row.
    static let childrenMasks: [UInt32] = (0..<PyramidGeometry.cardCount).map { index in
        guard let covering = PyramidGeometry.coveringIndices(of: index) else { return 0 }
        return (1 << UInt32(covering.left)) | (1 << UInt32(covering.right))
    }
}

// MARK: - Move generation and transitions

nonisolated private extension PyramidPlanner {
    /// Legal moves in a fixed, deterministic order: pyramid pairs by ascending
    /// slots (cover-pairs included), waste pairs by ascending slot, Kings, then
    /// draw and reset — removals first so equal-priority ties favor action.
    static func moves(from board: Board, position: Position) -> [Move] {
        var moves: [Move] = []

        for first in 0..<PyramidGeometry.cardCount where board.holdsCard(at: first) {
            let firstRank = position.slotRanks[first]
            let firstExposed = board.isExposed(first)
            for second in (first + 1)..<PyramidGeometry.cardCount where board.holdsCard(at: second) {
                guard firstRank + position.slotRanks[second] == PyramidGameRules.pairSum else {
                    continue
                }
                if firstExposed && board.isExposed(second) {
                    moves.append(.removePair(.pyramid(slot: first), .pyramid(slot: second)))
                } else if isCoverPair(parent: first, child: second, on: board) {
                    // A card's sole remaining cover is its partner: remove both.
                    moves.append(.removePair(.pyramid(slot: first), .pyramid(slot: second)))
                }
            }
        }

        if let wasteTop = board.wasteTopIndex {
            let wasteRank = position.stockRanks[wasteTop]
            for slot in 0..<PyramidGeometry.cardCount
            where board.holdsCard(at: slot)
                && board.isExposed(slot)
                && position.slotRanks[slot] + wasteRank == PyramidGameRules.pairSum {
                moves.append(.removePair(.pyramid(slot: slot), .wasteTop))
            }
        }

        let kingRank = Rank.king.rawValue
        for slot in 0..<PyramidGeometry.cardCount
        where board.holdsCard(at: slot)
            && board.isExposed(slot)
            && position.slotRanks[slot] == kingRank {
            moves.append(.removeKing(.pyramid(slot: slot)))
        }
        if let wasteTop = board.wasteTopIndex, position.stockRanks[wasteTop] == kingRank {
            moves.append(.removeKing(.wasteTop))
        }

        if board.nextDrawIndex(stockCount: position.stockRanks.count) != nil {
            moves.append(.draw)
        }
        if board.canResetStock(stockCount: position.stockRanks.count) {
            moves.append(.resetStock)
        }

        return moves
    }

    /// Whether `child` directly covers `parent`, is its only remaining cover, is
    /// itself exposed, and (checked by the caller) completes the pair sum.
    static func isCoverPair(parent: Int, child: Int, on board: Board) -> Bool {
        guard let covering = PyramidGeometry.coveringIndices(of: parent) else { return false }
        guard child == covering.left || child == covering.right else { return false }
        let otherCover = child == covering.left ? covering.right : covering.left
        guard !board.holdsCard(at: otherCover) else { return false }
        return board.isExposed(child)
    }

    /// Applies a generated move without re-validating legality (the search only
    /// feeds in moves it just generated).
    static func apply(_ move: Move, to board: Board, position: Position) -> Board {
        var next = board
        switch move {
        case .removePair(let first, let second):
            removeTarget(first, from: &next)
            removeTarget(second, from: &next)
        case .removeKing(let target):
            removeTarget(target, from: &next)
        case .draw:
            if let drawIndex = next.nextDrawIndex(stockCount: position.stockRanks.count) {
                next.cut = drawIndex + 1
            }
        case .resetStock:
            next.cut = 0
            next.passes += 1
        }
        return next
    }

    static func removeTarget(_ target: PairTarget, from board: inout Board) {
        switch target {
        case .pyramid(let slot):
            board.pyramidMask &= ~(1 << UInt32(slot))
        case .wasteTop:
            if let wasteTop = board.wasteTopIndex {
                board.stockRemovedMask |= 1 << UInt32(wasteTop)
                board.normalizeCut()
            }
        }
    }
}

// MARK: - Heuristic and dead-position proof

nonisolated private extension PyramidPlanner {
    /// Admissible lower bound on moves left to clear the pyramid: every King costs
    /// one removal, and each pair move lowers exactly one `max(count(r),
    /// count(13−r))` term by at most 1; draws and resets clear nothing.
    static func heuristic(for board: Board, position: Position) -> Int {
        let counts = rankCounts(inPyramidOf: board, position: position)
        var bound = counts[Rank.king.rawValue]
        for rank in 1...6 {
            bound += max(counts[rank], counts[PyramidGameRules.pairSum - rank])
        }
        return bound
    }

    /// Proof of unwinnability: each removal of a rank-`r` pyramid card consumes one
    /// rank-`13−r` partner, and partners can never exceed the pyramid's own
    /// `13−r` cards plus the stock survivors of that rank. The count is optimistic
    /// about reachability (every survivor is treated as playable), so it never
    /// over-prunes — an emptied stage-one graph is a proof.
    static func isProvablyUnwinnable(_ board: Board, position: Position) -> Bool {
        let pyramidCounts = rankCounts(inPyramidOf: board, position: position)
        var survivorCounts = [Int](repeating: 0, count: 14)
        for index in position.stockRanks.indices where !board.isRemoved(index) {
            survivorCounts[position.stockRanks[index]] += 1
        }
        for rank in 1...12 where pyramidCounts[rank] > 0 {
            let partnerRank = PyramidGameRules.pairSum - rank
            if pyramidCounts[rank] > pyramidCounts[partnerRank] + survivorCounts[partnerRank] {
                return true
            }
        }
        return false
    }

    static func rankCounts(inPyramidOf board: Board, position: Position) -> [Int] {
        var counts = [Int](repeating: 0, count: 14)
        var mask = board.pyramidMask
        while mask != 0 {
            let slot = mask.trailingZeroBitCount
            counts[position.slotRanks[slot]] += 1
            mask &= mask - 1
        }
        return counts
    }
}

// MARK: - Search

nonisolated private extension PyramidPlanner {
    struct Node {
        let board: Board
        let parent: Int
        let move: Move?
        let depth: Int
    }

    struct HeapEntry: HeapPrioritizable {
        let priority: Int
        let order: Int
        let index: Int

        func takesPriority(over other: HeapEntry) -> Bool {
            priority != other.priority ? priority > other.priority : order < other.order
        }
    }

    static let heuristicWeight = 10

    /// Stage one: weighted A* for a full winning line over the dead-pruned graph.
    /// `exhaustive` is true when the heap emptied within budget — with the exact
    /// prune, that is a proof the deal cannot be won.
    static func winSearch(
        from position: Position,
        limits: Limits
    ) -> (line: [Move]?, exhaustive: Bool) {
        if position.root.pyramidMask == 0 {
            return (line: [], exhaustive: true)
        }
        if isProvablyUnwinnable(position.root, position: position) {
            return (line: nil, exhaustive: true)
        }

        var nodes: [Node] = [Node(board: position.root, parent: -1, move: nil, depth: 0)]
        var visited: Set<UInt64> = [position.root.code]
        var heap = BinaryHeap<HeapEntry>()
        heap.push(
            HeapEntry(
                priority: -heuristicWeight * heuristic(for: position.root, position: position),
                order: 0,
                index: 0
            )
        )
        var order = 0
        var expansions = 0
        var wasTruncated = false

        while let entry = heap.pop() {
            let nodeIndex = entry.index
            let node = nodes[nodeIndex]

            if node.board.pyramidMask == 0 {
                return (line: line(to: nodeIndex, nodes: nodes), exhaustive: false)
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

            for move in moves(from: node.board, position: position) {
                let nextBoard = apply(move, to: node.board, position: position)
                guard visited.insert(nextBoard.code).inserted else { continue }
                guard !isProvablyUnwinnable(nextBoard, position: position) else { continue }

                nodes.append(
                    Node(board: nextBoard, parent: nodeIndex, move: move, depth: node.depth + 1)
                )
                order += 1
                // Min-first on f = g + W·h, expressed as a negated max priority.
                let f = node.depth + 1
                    + heuristicWeight * heuristic(for: nextBoard, position: position)
                heap.push(HeapEntry(priority: -f, order: order, index: nodes.count - 1))
            }
        }

        return (line: nil, exhaustive: !wasTruncated)
    }

    /// Stage two: best-first for the line clearing the most pyramid cards, over
    /// the unpruned graph — positions dead for winning can still hold the deepest
    /// clears.
    static func maxClearSearch(
        from position: Position,
        limits: Limits
    ) -> (line: [Move]?, exhaustive: Bool, bestRemaining: Int) {
        var nodes: [Node] = [Node(board: position.root, parent: -1, move: nil, depth: 0)]
        var visited: Set<UInt64> = [position.root.code]
        var heap = BinaryHeap<HeapEntry>()
        heap.push(HeapEntry(priority: 0, order: 0, index: 0))
        var order = 0
        var expansions = 0
        var wasTruncated = false
        let rootRemaining = position.root.remainingCount
        var best: (index: Int, remaining: Int, depth: Int)?

        while let entry = heap.pop() {
            let nodeIndex = entry.index
            let node = nodes[nodeIndex]
            let remaining = node.board.remainingCount

            if remaining < rootRemaining {
                let improvesBest = best.map {
                    remaining < $0.remaining
                        || (remaining == $0.remaining && node.depth < $0.depth)
                } ?? true
                if improvesBest {
                    best = (nodeIndex, remaining, node.depth)
                }
                if remaining == 0 { break }
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

            for move in moves(from: node.board, position: position) {
                let nextBoard = apply(move, to: node.board, position: position)
                guard visited.insert(nextBoard.code).inserted else { continue }

                nodes.append(
                    Node(board: nextBoard, parent: nodeIndex, move: move, depth: node.depth + 1)
                )
                order += 1
                // Best-first on cards cleared, shallow bias so equal clears prefer
                // short lines.
                let priority = (rootRemaining - nextBoard.remainingCount) * 256 - (node.depth + 1)
                heap.push(HeapEntry(priority: priority, order: order, index: nodes.count - 1))
            }
        }

        guard let best, let moves = line(to: best.index, nodes: nodes) else {
            return (line: nil, exhaustive: !wasTruncated, bestRemaining: rootRemaining)
        }
        return (line: moves, exhaustive: !wasTruncated, bestRemaining: best.remaining)
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
