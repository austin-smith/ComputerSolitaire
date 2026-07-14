import Foundation

/// Bounded best-first hint planner for Scorpion.
///
/// Searches sequences of real actions — tableau moves and the single stock
/// deal — up to a node/time budget, scoring positions by banked runs, revealed
/// cards, open columns, in-suit ordering, and same-suit knots. `bestLine`
/// returns the whole action sequence to the best position found that strictly
/// improves on the current one; `HintPlanner` follows the cached line action by
/// action: like Yukon, every Scorpion tableau move is reversible until a card
/// flips, the stock deals, or a run banks, so re-search after each move can
/// oscillate between equally attractive lines, while following one improving
/// line ratchets the position strictly forward.
///
/// The search reads the true state, including cards the player hasn't seen yet,
/// but it only ever recommends actions that are legal right now. Single-deck
/// building narrows the tree sharply: every non-king card has exactly one
/// landing card (its same-suit successor), which must be an exposed top, and
/// kings additionally target only empty columns. That uniqueness also makes
/// Spider's same-suit-unbind prune unnecessary — a card already lying on its
/// successor has no other landing card anywhere, so no action re-hosts it.
/// Searching through the deal lets the planner groom the tableau *before*
/// recommending it; the deal itself is score-neutral (the heuristic has no
/// stock term), so deal-crossing lines only win when the flips and joins they
/// enable pay for them. Scorpion banks completed runs automatically and they
/// never return, so there is no rollback stage.
///
/// Measured in the `tools/hint-probe` ledger: following every hint wins 14.8%
/// of 500 seeded deals versus the random control's 2.8%, with zero revisit
/// events — at the level of published practical win rates for Scorpion.
nonisolated enum ScorpionPlanner {
    struct Limits {
        var maxNodes: Int
        var maxDepth: Int
        var deadline: Date?

        // Scorpion branches narrowest of the tableau variants (one landing
        // card per non-king selection), so 30k nodes reaches deep lines.
        // Affordable because lines are cached: the search only runs when a
        // followed line runs out, not on every hint.
        init(maxNodes: Int = 30_000, maxDepth: Int = 64, deadline: Date? = nil) {
            self.maxNodes = maxNodes
            self.maxDepth = maxDepth
            self.deadline = deadline
        }
    }

    enum PlannedAction {
        case move(selection: Selection, destination: Destination)
        case stockDeal
    }

    enum SearchOutcome {
        /// Actions leading to the best strictly-improving position found.
        case line([PlannedAction])
        /// Nothing within the horizon improves on the current position. When the
        /// search ran out of reachable states — rather than nodes, depth, or time —
        /// that is proof the tableau cannot progress without the deal.
        case noProgress(searchWasExhaustive: Bool)
    }

    static func bestHint(in state: GameState, limits: Limits = Limits()) -> HintAdvisor.Hint? {
        guard case .line(let actions) = bestLine(in: state, limits: limits),
              let action = actions.first else {
            return nil
        }
        switch action {
        case .move(let selection, let destination):
            return .move(HintAdvisor.HintMove(selection: selection, destination: destination))
        case .stockDeal:
            return .stockTap
        }
    }

    /// Exact (non-canonical) position key, stable across `Card` identities; used to
    /// look up the cached line as the player follows it.
    static func stateKey(for state: GameState) -> String {
        var key = String()
        key.reserveCapacity(160)
        func append(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            key.append(String(UnicodeScalar(UInt8(65 + suitValue * 2 + (card.isFaceUp ? 1 : 0)))))
            key.append(String(UnicodeScalar(UInt8(97 + card.rank.rawValue))))
        }
        // The stock deals exactly once, wholesale, so its count (3 or 0)
        // identifies its exact contents.
        key.append("#\(state.stock.count)")
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

    /// Maps each position along the line to the action to play there, so consecutive
    /// hints are instant while the player follows (or plays ahead along) the line.
    static func keyedActions(
        along line: [PlannedAction],
        from state: GameState
    ) -> [String: PlannedAction] {
        var keyed: [String: PlannedAction] = [:]
        var current = state
        for action in line {
            keyed[stateKey(for: current)] = action
            guard let next = apply(action, to: current) else { break }
            current = next
        }
        return keyed
    }

    static func bestLine(in state: GameState, limits: Limits = Limits()) -> SearchOutcome {
        guard state.variant == .scorpion else { return .noProgress(searchWasExhaustive: false) }
        return search(in: state, limits: limits)
    }
}

// MARK: - Search internals

nonisolated private extension ScorpionPlanner {
    static func search(in state: GameState, limits: Limits) -> SearchOutcome {
        let rootScore = score(state)
        var nodes: [Node] = [Node(state: state, parent: -1, action: nil, depth: 0, score: rootScore)]
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
            // A line that reveals a card or banks a run is a solid hint; once one
            // is in hand, cap how long we keep hunting for something better. The
            // floor matches Yukon's: Scorpion's narrow branching keeps each
            // expansion cheap.
            if let best, best.score - rootScore >= 20, expansions >= 16_384 {
                break
            }

            for action in actions(from: node.state) {
                guard let nextState = apply(action, to: node.state) else { continue }
                guard visited.insert(stateHash(nextState)).inserted else { continue }

                let nextScore = score(nextState)
                nodes.append(
                    Node(
                        state: nextState,
                        parent: nodeIndex,
                        action: action,
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

        guard let best, let actions = line(to: best.index, nodes: nodes) else {
            return .noProgress(searchWasExhaustive: !wasTruncated)
        }
        return .line(actions)
    }

    struct Node {
        let state: GameState
        let parent: Int
        let action: PlannedAction?
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
        var suitedRunBonus = 0
        var sameSuitInversions = 0
        for pile in state.tableau {
            if pile.isEmpty { emptyPiles += 1 }
            var suitedRunLength = 1
            for index in pile.indices {
                let card = pile[index]
                if card.isFaceUp {
                    if index + 1 < pile.count {
                        let upper = pile[index + 1]
                        if upper.suit == card.suit,
                           upper.rank.rawValue == card.rank.rawValue - 1 {
                            suitedRunLength += 1
                            continue
                        }
                    }
                } else {
                    hiddenCount += 1
                }
                // The suited run ends here (or the pile did); credit it.
                suitedRunBonus += (suitedRunLength - 1) * (suitedRunLength - 1)
                suitedRunLength = 1
            }
            for index in pile.indices {
                let card = pile[index]
                for upperIndex in (index + 1)..<pile.count
                where pile[upperIndex].suit == card.suit && pile[upperIndex].rank > card.rank {
                    sameSuitInversions += 1
                }
            }
        }
        let bankedCards = state.foundations.reduce(0) { $0 + $1.count }
        // Between reveals, progress in Scorpion is untangling into suits: reward
        // suited runs quadratically in their length — only thirteen-long runs
        // bank, and a linear count would never prefer consolidating two short
        // runs into one long one — and penalize burying a card under a higher
        // card of its own suit (that card must move again, onto its unique
        // landing card, before the suit can finish). Off-suit descending pairs
        // earn nothing: they neither move as a unit nor enable a landing. Open
        // columns rate between Yukon's 4 and Spider's 10 — Scorpion's take Kings
        // only and nothing forces filling them — and stay below one reveal so
        // the search digs rather than hoards. No stock term: rewarding the deal
        // would burn the three-card reserve before the tableau is groomed.
        return bankedCards * 20
            - hiddenCount * 25
            + emptyPiles * 5
            + suitedRunBonus
            - sameSuitInversions * 3
    }

    static func actions(from state: GameState) -> [PlannedAction] {
        // Empty columns are interchangeable only within their deal class:
        // while the stock is undealt, each of columns 0–2 still awaits its own
        // specific stock card, so they stay distinct from each other and from
        // the rest; once the stock is spent every column is interchangeable.
        // Searching a drop into every interchangeable twin only multiplies
        // column-permuted duplicates, so canonicalize to the class's first.
        // (Players can still drop on any empty column.)
        let interchangeableStart = state.stock.isEmpty ? 0 : 3
        let firstInterchangeableEmpty = state.tableau.indices.first {
            $0 >= interchangeableStart && state.tableau[$0].isEmpty
        }
        var actions: [PlannedAction] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                if case .tableau(let index) = destination,
                   state.tableau[index].isEmpty,
                   index >= interchangeableStart,
                   index != firstInterchangeableEmpty {
                    continue
                }
                actions.append(.move(selection: selection, destination: destination))
            }
        }
        if ScorpionGameRules.canDealFromStock(state: state) {
            actions.append(.stockDeal)
        }
        return actions
    }

    /// Applies an action without re-validating legality: the planner only feeds
    /// in actions it just generated, and revalidating each one there dominates
    /// search cost. Mirrors the session's move effects, including banking any
    /// completed run.
    static func apply(_ action: PlannedAction, to state: GameState) -> GameState? {
        var nextState = state
        switch action {
        case .move(let selection, let destination):
            guard case .tableau(let pile, let index) = selection.source else { return nil }
            nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
            if let topIndex = nextState.tableau[pile].indices.last,
               !nextState.tableau[pile][topIndex].isFaceUp {
                nextState.tableau[pile][topIndex].isFaceUp = true
            }
            guard case .tableau(let destinationIndex) = destination else { return nil }
            nextState.tableau[destinationIndex].append(contentsOf: selection.cards)
            ScorpionGameRules.resolveCompletedRuns(in: &nextState)
        case .stockDeal:
            guard ScorpionGameRules.dealStock(in: &nextState) != nil else { return nil }
        }
        return nextState
    }

    /// FNV-1a over a canonical layout: foundations collapse to per-suit banked
    /// flags (a banked run's contents are implied by its suit), the stock
    /// contributes only its count (it deals once, wholesale), and tableau piles
    /// are sorted before mixing — but only the piles that are strategically
    /// interchangeable. While the stock is undealt, each of columns 0–2 awaits
    /// its own specific dealt card, so those three mix positionally and only
    /// columns 3–6 sort; once the stock is spent, no rule reads a column's
    /// index, so all seven sort. Sorting the distinct columns would merge
    /// strategically different positions and could prune the better line.
    static func stateHash(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) {
            hash = (hash ^ UInt64(value)) &* 0x100000001b3
        }
        func encode(card: Card) -> UInt8 {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            return UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0))
        }
        mix(UInt8(state.stock.count))
        for suit in Suit.allCases {
            mix(0xFE)
            let bankedRuns = state.foundations.count { $0.first?.suit == suit }
            mix(UInt8(bankedRuns))
        }
        let positionalCount = state.stock.isEmpty ? 0 : 3
        for pile in state.tableau.prefix(positionalCount) {
            mix(0xFD)
            for card in pile { mix(encode(card: card)) }
        }
        let encodedPiles = state.tableau.dropFirst(positionalCount)
            .map { pile in pile.map { encode(card: $0) } }
            .sorted { $0.lexicographicallyPrecedes($1) }
        for pile in encodedPiles {
            mix(0xFD)
            for value in pile { mix(value) }
        }
        return hash
    }

    static func line(to index: Int, nodes: [Node]) -> [PlannedAction]? {
        var actions: [PlannedAction] = []
        var cursor = index
        while cursor >= 0, nodes[cursor].parent >= 0 {
            if let action = nodes[cursor].action {
                actions.append(action)
            }
            cursor = nodes[cursor].parent
        }
        guard !actions.isEmpty else { return nil }
        return actions.reversed()
    }
}
