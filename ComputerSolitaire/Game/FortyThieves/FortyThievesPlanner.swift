import Foundation

/// Bounded best-first hint planner for Forty Thieves.
///
/// Searches sequences of real actions — single-card tableau and waste moves,
/// foundation banks, and stock taps — up to a node/time budget, scoring
/// positions by banked cards, open columns, suited descending order, developed
/// stock/waste cards, and how deeply the next foundation-needed cards are
/// buried. `bestLine` returns the whole action sequence to the best position
/// found that strictly improves on the current one; `HintPlanner` follows the
/// cached line action by action: like Spider and Yukon, every Forty Thieves
/// tableau move is reversible until a card banks or the stock turns, so
/// re-search after each move can oscillate between equally attractive lines,
/// while following one improving line ratchets the position strictly forward.
///
/// The search reads the true state, including the face-down stock order, but
/// it only ever recommends actions that are legal right now. Searching through
/// stock taps is what lets the planner line up the plays a buried stock card
/// enables *before* recommending the tap; the tap itself is score-neutral
/// (each undeveloped stock or waste card carries the same penalty), so
/// tap-crossing lines only win when the plays they enable pay for them.
/// Foundations are locked and `candidateSelections` offers no foundation
/// sources for rollback-free variants, so there is no rollback stage.
enum FortyThievesPlanner {
    struct Limits {
        var maxNodes: Int
        var maxDepth: Int
        var deadline: Date?

        // Forty Thieves branches in Spider's class (eleven sources, few legal
        // landings each, plus the tap), so it shares Spider's budget.
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
        case stockTap
    }

    enum SearchOutcome {
        /// Actions leading to the best strictly-improving position found.
        case line([PlannedAction])
        /// Nothing within the horizon improves on the current position. When the
        /// search ran out of reachable states — rather than nodes, depth, or time —
        /// that is proof the position cannot progress without a stock tap.
        case noProgress(searchWasExhaustive: Bool)
    }

    static func bestHint(in state: GameState, limits: Limits = Limits()) -> HintAdvisor.Hint? {
        guard case .line(let actions) = bestLine(in: state, limits: limits),
              let action = actions.first else {
            return nil
        }
        return materialize(action, in: state)
    }

    /// Exact (non-canonical) position key, stable across `Card` identities; used to
    /// look up the cached line as the player follows it.
    static func stateKey(for state: GameState) -> String {
        var key = String()
        key.reserveCapacity(256)
        func append(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            key.append(String(UnicodeScalar(UInt8(65 + suitValue * 2 + (card.isFaceUp ? 1 : 0)))))
            key.append(String(UnicodeScalar(UInt8(97 + card.rank.rawValue))))
        }
        // Within one game the single-pass stock only ever shrinks off a fixed
        // order, so its count identifies its exact contents. The waste is spelled
        // out in full: plays remove waste cards, so its contents are not
        // derivable from the stock count, and its buried order shapes the future.
        key.append("#\(state.stock.count)~")
        for card in state.waste { append(card: card) }
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

    /// Re-validates a planned action against the live state; a stale cached
    /// action surfaces as nil (and triggers a fresh search) rather than as an
    /// illegal hint.
    static func materialize(_ action: PlannedAction, in state: GameState) -> HintAdvisor.Hint? {
        switch action {
        case .move(let selection, let destination):
            guard AutoMoveAdvisor.selectionMatchesState(selection, in: state),
                  AutoMoveAdvisor.legalDestinations(for: selection, in: state)
                      .contains(destination) else {
                return nil
            }
            return .move(HintAdvisor.HintMove(selection: selection, destination: destination))
        case .stockTap:
            guard !state.stock.isEmpty else { return nil }
            return .stockTap
        }
    }

    static func bestLine(in state: GameState, limits: Limits = Limits()) -> SearchOutcome {
        guard state.variant == .fortyThieves else { return .noProgress(searchWasExhaustive: false) }
        return search(in: state, limits: limits)
    }

    /// Applies an action without re-validating legality: the planner only feeds
    /// in actions it just generated (the hint probe reuses this as the same
    /// pure logic the session performs), and revalidating each one there
    /// dominates search cost. Mirrors the session's move effects.
    static func apply(_ action: PlannedAction, to state: GameState) -> GameState? {
        var nextState = state
        switch action {
        case .move(let selection, let destination):
            switch selection.source {
            case .tableau(let pile, let index):
                nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
            case .waste:
                _ = nextState.waste.popLast()
                nextState.wasteDrawCount = min(1, nextState.waste.count)
            case .foundation, .freeCell, .pyramid, .triPeaks:
                return nil
            }
            switch destination {
            case .tableau(let index):
                nextState.tableau[index].append(contentsOf: selection.cards)
            case .foundation(let index):
                nextState.foundations[index].append(contentsOf: selection.cards)
            case .freeCell, .pyramid, .waste, .discard:
                return nil
            }
        case .stockTap:
            guard !nextState.stock.isEmpty else { return nil }
            var card = nextState.stock.removeLast()
            card.isFaceUp = true
            nextState.waste.append(card)
            nextState.wasteDrawCount = 1
        }
        return nextState
    }
}

// MARK: - Search internals

private extension FortyThievesPlanner {
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
            // A line that banks a card or opens a column is a solid hint; once
            // one is in hand, cap how long we keep hunting for something better.
            // Spider's floor, for the same wide-branching economics.
            if let best, best.score - rootScore >= 20, expansions >= 8_192 {
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
        var emptyColumns = 0
        var suitedPairs = 0
        for pile in state.tableau {
            if pile.isEmpty {
                emptyColumns += 1
                continue
            }
            for index in 1..<pile.count {
                let lower = pile[index - 1]
                let upper = pile[index]
                if upper.suit == lower.suit, upper.rank.rawValue == lower.rank.rawValue - 1 {
                    suitedPairs += 1
                }
            }
        }
        let bankedCards = state.foundations.reduce(0) { $0 + $1.count }
        let undevelopedCount = state.stock.count + state.waste.count
        // Banking is the only permanent progress and sets the scale. Open
        // columns are Forty Thieves' scarcest resource — the one unburying
        // mechanism and the only landing that takes any card — so they price
        // above Spider's rate but below one bank, so improving lines still
        // spend them rather than hoard. Every legal landing forms a suited
        // descending pair, making pairs the between-banks ordering signal.
        // Developing cards out of the stock/waste counts as progress (so a
        // stock tap is score-neutral and playing off the waste beats an
        // equivalent tableau play), and each card covering a copy of the next
        // foundation-needed card of any suit is a dig the line still owes.
        return bankedCards * 20
            + emptyColumns * 12
            + suitedPairs
            - undevelopedCount * 2
            - nextNeededBurialDepth(state) * 2
    }

    /// How many cards sit on top of the most accessible tableau copy of each
    /// foundation's next needed card, summed over the eight foundations. The
    /// two deck copies are interchangeable, so only the shallower one counts;
    /// copies still in the stock or waste owe no dig (the undeveloped term
    /// already carries them).
    static func nextNeededBurialDepth(_ state: GameState) -> Int {
        var total = 0
        for suit in Suit.allCases {
            var heights = state.foundations
                .filter { $0.first?.suit == suit }
                .map(\.count)
            while heights.count < 2 {
                heights.append(0)
            }
            for height in heights {
                let neededRank = height + 1
                guard neededRank <= Rank.king.rawValue else { continue }
                var shallowestBurial: Int?
                for pile in state.tableau {
                    for index in pile.indices
                    where pile[index].suit == suit && pile[index].rank.rawValue == neededRank {
                        let burial = pile.count - 1 - index
                        shallowestBurial = min(shallowestBurial ?? burial, burial)
                    }
                }
                total += shallowestBurial ?? 0
            }
        }
        return total
    }

    static func actions(from state: GameState) -> [PlannedAction] {
        let firstEmptyColumn = state.tableau.firstIndex(where: \.isEmpty)
        var actions: [PlannedAction] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            // Exact-equivalence canonicalizations, all invisible to the player:
            // the two decks make twin destinations common, and searching both
            // of a twin pair only multiplies permuted duplicates.
            var tookFoundation = false
            var seenTableauTops: [(suit: Suit, rank: Rank)] = []
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                switch destination {
                case .foundation:
                    // Two foundations legal for the same card hold identical
                    // runs by construction (same suit, same height), so keep
                    // the first.
                    if tookFoundation { continue }
                    tookFoundation = true
                case .tableau(let index):
                    if state.tableau[index].isEmpty {
                        // Empty columns are interchangeable: canonicalize to the
                        // first. (Players can still drop on any empty column.)
                        if index != firstEmptyColumn { continue }
                    } else if let top = state.tableau[index].last {
                        // Twin tops are interchangeable landings: keep the
                        // lower-indexed column.
                        if seenTableauTops.contains(where: { $0.suit == top.suit && $0.rank == top.rank }) {
                            continue
                        }
                        seenTableauTops.append((top.suit, top.rank))
                    }
                case .freeCell, .pyramid, .waste, .discard:
                    continue
                }
                actions.append(.move(selection: selection, destination: destination))
            }
        }
        if !state.stock.isEmpty {
            actions.append(.stockTap)
        }
        return actions
    }

    /// FNV-1a over a canonical layout: tableau piles are sorted before mixing
    /// because Forty Thieves columns are strategically interchangeable, each
    /// suit's two foundations collapse to their sorted height pair (which twin
    /// pile holds which run carries nothing), and the stock contributes only
    /// its count (its order never changes within one game). The waste is mixed
    /// in full — its buried order matters. Cards hash by content, so the twin
    /// cards of the two decks collapse identical positions to one visited entry.
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
        mix(0xFC)
        for card in state.waste { mix(encode(card: card)) }
        for suit in Suit.allCases {
            mix(0xFE)
            let heights = state.foundations
                .filter { $0.first?.suit == suit }
                .map(\.count)
                .sorted()
            for height in heights { mix(UInt8(height)) }
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
