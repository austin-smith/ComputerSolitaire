import Foundation

/// Bounded best-first hint planner for Yukon.
///
/// Searches sequences of real moves up to a node/time budget, scoring positions by
/// foundation progress, revealed cards, open columns, and how untangled the face-up
/// stacks are. `bestLine` returns the whole move sequence to the best position found
/// that strictly improves on the current one; nil means nothing within the horizon
/// makes progress (the game is stuck or lost). `HintPlanner` follows the cached line
/// move by move: because every Yukon tableau move is reversible until a card flips,
/// re-searching after each move can oscillate between equally attractive lines, while
/// following one improving line to its end ratchets the position strictly forward.
///
/// The search reads the true state, including cards the player hasn't seen yet, but it
/// only ever recommends actions that are legal right now. Yukon has no stock, so this
/// never returns `.stockTap`.
///
/// The search runs in two stages. The primary stage excludes foundation-to-tableau
/// rollbacks: including them measurably degrades line quality (bank/unbank churn
/// wanders lines through repeated territory and dilutes the node budget). Only when
/// the primary stage exhausts its graph without finding progress does a second stage
/// search the full move set including rollbacks — a rollback can be the only way to
/// unbury a card whose landing spots were banked prematurely, so only a search over
/// every legal move may declare the position provably stuck.
enum YukonPlanner {
    struct Limits {
        var maxNodes: Int
        var maxDepth: Int
        var deadline: Date?

        // Yukon branches 3-5x wider than Klondike (any face-up card is pickable),
        // so a deeper node budget buys back comparable effective search depth. The
        // budget is affordable because lines are cached: the search only runs when a
        // followed line runs out, not on every hint.
        init(maxNodes: Int = 40_000, maxDepth: Int = 64, deadline: Date? = nil) {
            self.maxNodes = maxNodes
            self.maxDepth = maxDepth
            self.deadline = deadline
        }
    }

    struct PlannedMove {
        let selection: Selection
        let destination: Destination
    }

    enum SearchOutcome {
        /// Moves leading to the best strictly-improving position found.
        case line([PlannedMove])
        /// Nothing within the horizon improves on the current position. When the
        /// search ran out of reachable states — rather than nodes, depth, or time —
        /// that is proof the position cannot progress, and the hint should say so
        /// instead of nudging in circles.
        case noProgress(searchWasExhaustive: Bool)
    }

    static func bestHint(in state: GameState, limits: Limits = Limits()) -> HintAdvisor.Hint? {
        guard case .line(let moves) = bestLine(in: state, limits: limits),
              let move = moves.first else {
            return nil
        }
        return .move(HintAdvisor.HintMove(selection: move.selection, destination: move.destination))
    }

    /// Exact (non-canonical) position key, stable across `Card` identities; used to
    /// look up the cached line as the player follows it.
    static func stateKey(for state: GameState) -> String {
        var key = String()
        key.reserveCapacity(128)
        func append(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            key.append(String(UnicodeScalar(UInt8(65 + suitValue * 2 + (card.isFaceUp ? 1 : 0)))))
            key.append(String(UnicodeScalar(UInt8(97 + card.rank.rawValue))))
        }
        for pile in state.foundations {
            key.append("|")
            for card in pile { append(card: card) }
        }
        for pile in state.tableau {
            key.append("/")
            for card in pile { append(card: card) }
        }
        return key
    }

    /// Maps each position along the line to the move to play there, so consecutive
    /// hints are instant while the player follows (or plays ahead along) the line.
    static func keyedMoves(along line: [PlannedMove], from state: GameState) -> [String: PlannedMove] {
        var keyed: [String: PlannedMove] = [:]
        var current = state
        for move in line {
            keyed[stateKey(for: current)] = move
            guard let next = apply(move, to: current) else { break }
            current = next
        }
        return keyed
    }

    static func bestLine(in state: GameState, limits: Limits = Limits()) -> SearchOutcome {
        guard state.variant == .yukon else { return .noProgress(searchWasExhaustive: false) }

        switch search(in: state, limits: limits, includesFoundationRollbacks: false) {
        case .line(let moves):
            return .line(moves)
        case .noProgress(searchWasExhaustive: false):
            return .noProgress(searchWasExhaustive: false)
        case .noProgress(searchWasExhaustive: true):
            // The rollback-free graph holds no progress. Before declaring the
            // position stuck, search the full move set: a foundation rollback can
            // be the only rescue when a needed landing card was banked early.
            return search(in: state, limits: limits, includesFoundationRollbacks: true)
        }
    }
}

// MARK: - Search internals

private extension YukonPlanner {
    static func search(
        in state: GameState,
        limits: Limits,
        includesFoundationRollbacks: Bool
    ) -> SearchOutcome {
        let rootScore = score(state)
        var nodes: [Node] = [Node(state: state, parent: -1, move: nil, depth: 0, score: rootScore)]
        var visited: Set<UInt64> = [stateHash(state)]
        var heap = BinaryHeap<HeapEntry>()
        heap.push(HeapEntry(priority: rootScore, order: 0, index: 0))
        var order = 0
        var expansions = 0
        var wasTruncated = false
        var best: (index: Int, score: Int, depth: Int)?

        while let entry = heap.pop() {
            let nodeIndex = entry.index
            let node = nodes[nodeIndex]

            if node.score > rootScore {
                let improvesBest = best.map {
                    node.score > $0.score || (node.score == $0.score && node.depth < $0.depth)
                } ?? true
                if improvesBest {
                    best = (nodeIndex, node.score, node.depth)
                }
                if node.state.isWon { break }
            }

            guard node.depth < limits.maxDepth else {
                wasTruncated = true
                continue
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
            // A line that reveals a card or banks a foundation card is a solid hint;
            // once one is in hand, cap how long we keep hunting for something better.
            // The floor is higher than Klondike's 768: lines are cached, so the search
            // runs once per followed line and can afford to pick lines more carefully.
            if let best, best.score - rootScore >= 20, expansions >= 16384 {
                break
            }

            for move in moves(
                from: node.state,
                includesFoundationRollbacks: includesFoundationRollbacks
            ) {
                guard let nextState = apply(move, to: node.state) else { continue }
                guard visited.insert(stateHash(nextState)).inserted else { continue }

                let nextScore = score(nextState)
                nodes.append(
                    Node(
                        state: nextState,
                        parent: nodeIndex,
                        move: move,
                        depth: node.depth + 1,
                        score: nextScore
                    )
                )
                order += 1
                // Best-first on score, shallow bias so equal outcomes prefer short lines.
                heap.push(
                    HeapEntry(
                        priority: nextScore * 4 - (node.depth + 1),
                        order: order,
                        index: nodes.count - 1
                    )
                )
            }
        }

        guard let best, let moves = line(to: best.index, nodes: nodes) else {
            return .noProgress(searchWasExhaustive: !wasTruncated)
        }
        return .line(moves)
    }

    struct Node {
        let state: GameState
        let parent: Int
        let move: PlannedMove?
        let depth: Int
        let score: Int
    }

    struct HeapEntry: HeapPrioritizable {
        let priority: Int
        let order: Int
        let index: Int

        func takesPriority(over other: HeapEntry) -> Bool {
            priority != other.priority ? priority > other.priority : order < other.order
        }
    }

    static func score(_ state: GameState) -> Int {
        var hiddenCount = 0
        var emptyPiles = 0
        var sequencedPairs = 0
        var sameSuitInversions = 0
        for pile in state.tableau {
            if pile.isEmpty { emptyPiles += 1 }
            for index in pile.indices {
                let card = pile[index]
                if card.isFaceUp {
                    if index + 1 < pile.count {
                        let upper = pile[index + 1]
                        if upper.suit.isRed != card.suit.isRed,
                           upper.rank.rawValue == card.rank.rawValue - 1 {
                            sequencedPairs += 1
                        }
                    }
                } else {
                    hiddenCount += 1
                }
                for upperIndex in (index + 1)..<pile.count
                where pile[upperIndex].suit == card.suit && pile[upperIndex].rank > card.rank {
                    sameSuitInversions += 1
                }
            }
        }
        let foundationCount = state.foundations.reduce(0) { $0 + $1.count }
        // Between reveals, progress in Yukon is untangling: reward in-sequence pairs
        // (a full tidy-up still scores below one reveal), penalize burying a card
        // under a higher card of its own suit (that card must move again before the
        // suit can finish), and penalize cards stacked above the next rank each
        // foundation needs, so the search digs with purpose.
        return foundationCount * 20
            - hiddenCount * 25
            + emptyPiles * 4
            + sequencedPairs
            - sameSuitInversions * 3
            - nextNeededBurial(in: state) * 2
    }

    /// Total number of cards stacked above each card that some foundation needs next.
    static func nextNeededBurial(in state: GameState) -> Int {
        var topRankBySuit: [Suit: Int] = [:]
        for foundation in state.foundations {
            if let top = foundation.last {
                topRankBySuit[top.suit] = top.rank.rawValue
            }
        }

        var burial = 0
        for suit in Suit.allCases {
            let neededRank = (topRankBySuit[suit] ?? 0) + 1
            guard neededRank <= Rank.king.rawValue else { continue }
            for pile in state.tableau {
                if let index = pile.firstIndex(where: { $0.suit == suit && $0.rank.rawValue == neededRank }) {
                    burial += pile.count - 1 - index
                    break
                }
            }
        }
        return burial
    }

    static func moves(
        from state: GameState,
        includesFoundationRollbacks: Bool
    ) -> [PlannedMove] {
        let firstEmptyColumn = state.tableau.firstIndex(where: \.isEmpty)
        var moves: [PlannedMove] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            if case .foundation = selection.source, !includesFoundationRollbacks {
                continue
            }
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                // Empty columns are interchangeable: searching a drop into every one
                // only multiplies column-permuted twins, so canonicalize to the first.
                // (Players can still drop on any empty column.)
                if case .tableau(let index) = destination,
                   state.tableau[index].isEmpty,
                   index != firstEmptyColumn {
                    continue
                }
                moves.append(PlannedMove(selection: selection, destination: destination))
            }
        }
        return moves
    }

    /// Applies a move without re-validating legality: the planner only feeds in
    /// moves it just generated from `legalDestinations`, and revalidating each one
    /// there dominates search cost. Mirrors the session's move effects.
    static func apply(_ move: PlannedMove, to state: GameState) -> GameState? {
        var nextState = state
        switch move.selection.source {
        case .tableau(let pile, let index):
            nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
            if let topIndex = nextState.tableau[pile].indices.last,
               !nextState.tableau[pile][topIndex].isFaceUp {
                nextState.tableau[pile][topIndex].isFaceUp = true
            }
        case .foundation(let pile):
            _ = nextState.foundations[pile].popLast()
        case .waste, .freeCell, .pyramid:
            // Yukon has no waste, free cells, or pyramid.
            return nil
        }
        switch move.destination {
        case .foundation(let index):
            guard move.selection.cards.count == 1, let card = move.selection.cards.first else {
                return nil
            }
            nextState.foundations[index].append(card)
        case .tableau(let index):
            nextState.tableau[index].append(contentsOf: move.selection.cards)
        case .freeCell, .pyramid, .waste, .discard:
            return nil
        }
        return nextState
    }

    /// FNV-1a over a canonical layout: tableau piles are sorted before mixing because
    /// Yukon columns are strategically interchangeable, so column-permuted twins
    /// collapse to one visited entry. A 64-bit collision inside one search's visited
    /// set (a few thousand entries) is vanishingly unlikely and merely prunes one line.
    static func stateHash(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) {
            hash = (hash ^ UInt64(value)) &* 0x100000001b3
        }
        func encode(card: Card) -> UInt8 {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            return UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0))
        }
        for pile in state.foundations {
            mix(0xFE)
            for card in pile { mix(encode(card: card)) }
        }
        let encodedPiles = state.tableau
            .map { pile in pile.map { encode(card: $0) } }
            .sorted { $0.lexicographicallyPrecedes($1) }
        for pile in encodedPiles {
            mix(0xFD)
            for value in pile { mix(value) }
        }
        return hash
    }

    static func line(to index: Int, nodes: [Node]) -> [PlannedMove]? {
        var moves: [PlannedMove] = []
        var cursor = index
        while cursor >= 0, nodes[cursor].parent >= 0 {
            if let move = nodes[cursor].move {
                moves.append(move)
            }
            cursor = nodes[cursor].parent
        }
        guard !moves.isEmpty else { return nil }
        return moves.reversed()
    }
}
