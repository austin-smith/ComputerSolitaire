import Foundation

/// Bounded best-first hint planner for Spider.
///
/// Searches sequences of real actions — tableau moves and stock deals — up to a
/// node/time budget, scoring positions by banked runs, revealed cards, open
/// columns, and how much of the tableau sits in descending (ideally suited)
/// order. `bestLine` returns the whole action sequence to the best position
/// found that strictly improves on the current one; `HintPlanner` follows the
/// cached line action by action: like Yukon, every Spider tableau move is
/// reversible until a card flips, a row is dealt, or a run banks, so re-search
/// after each move can oscillate between equally attractive lines, while
/// following one improving line ratchets the position strictly forward.
///
/// The search reads the true state, including cards the player hasn't seen yet,
/// but it only ever recommends actions that are legal right now. Searching
/// through stock deals is what lets the planner groom the tableau *before*
/// recommending a deal; the deal itself is score-neutral (the heuristic has no
/// stock term), so deal-crossing lines only win when the flips and joins they
/// enable pay for them. Spider banks completed runs automatically and they
/// never return, so there is no rollback stage.
enum SpiderPlanner {
    struct Limits {
        var maxNodes: Int
        var maxDepth: Int
        var deadline: Date?

        // Spider branches wider than Yukon (ten piles, and most tops accept
        // several cards), so each expansion costs more; a 30k-node budget still
        // reaches the next flip or tidy target because the heap is score-driven.
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
        /// that is proof the tableau cannot progress without a deal.
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
        key.reserveCapacity(256)
        func append(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            key.append(String(UnicodeScalar(UInt8(65 + suitValue * 2 + (card.isFaceUp ? 1 : 0)))))
            key.append(String(UnicodeScalar(UInt8(97 + card.rank.rawValue))))
        }
        // Within one game the stock only ever shrinks by fixed ten-card rows,
        // so its count identifies its exact contents.
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
        guard state.variant == .spider else { return .noProgress(searchWasExhaustive: false) }
        return search(in: state, limits: limits)
    }

    /// The way forward when no improving line exists but stock remains is to
    /// deal. Dealing first requires filling every empty column, and filling
    /// always *costs* score (it spends an open column), so no improving line
    /// can contain it — worse, from any intermediate filled position, moving
    /// the filler back out "improves" again, so planning move-by-move would
    /// cycle. The whole preparation — the best one-ply fill for each empty
    /// column, then the deal — is therefore built as one line for `HintPlanner`
    /// to cache and follow without re-planning in between. Returns nil when
    /// the stock is out or an empty column cannot be filled (the position is
    /// genuinely finished).
    static func dealPreparationLine(in state: GameState) -> [PlannedAction]? {
        guard state.variant == .spider, !state.stock.isEmpty else { return nil }
        var current = state
        var line: [PlannedAction] = []
        var fills = 0
        while !SpiderGameRules.canDealFromStock(state: current) {
            guard fills < current.tableau.count,
                  let fill = bestFill(in: current),
                  let next = apply(fill, to: current) else {
                return nil
            }
            line.append(fill)
            current = next
            fills += 1
        }
        line.append(.stockDeal)
        return line
    }
}

// MARK: - Search internals

private extension SpiderPlanner {
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
            // floor is lower than Yukon's 16384 because Spider's wider branching
            // makes each expansion several times as expensive.
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
        var hiddenCount = 0
        var emptyPiles = 0
        var descendingPairs = 0
        var breaks = 0
        var suitedRunBonus = 0
        for pile in state.tableau {
            if pile.isEmpty { emptyPiles += 1 }
            var suitedRunLength = 1
            for index in pile.indices {
                let card = pile[index]
                if card.isFaceUp {
                    if index + 1 < pile.count {
                        let upper = pile[index + 1]
                        if upper.rank.rawValue == card.rank.rawValue - 1 {
                            descendingPairs += 1
                            if upper.suit == card.suit {
                                suitedRunLength += 1
                                continue
                            }
                        } else {
                            // Only deals create these junctions (every landing
                            // is one-higher or an empty pile); each one blocks
                            // its pile until the junk above moves off.
                            breaks += 1
                        }
                    }
                } else {
                    hiddenCount += 1
                }
                // The suited run ends here (or the pile did); credit it.
                suitedRunBonus += (suitedRunLength - 1) * (suitedRunLength - 1)
                suitedRunLength = 1
            }
        }
        let bankedCards = state.foundations.reduce(0) { $0 + $1.count }
        // Between reveals, progress in Spider is ordering: reward any in-order
        // pair (it survives deals and keeps piles playable), reward suited runs
        // quadratically in their length — only thirteen-long suited runs bank,
        // and a linear pair count would never prefer consolidating two short
        // runs into one long one — and prize open columns well above Yukon's
        // rate (they are Spider's maneuvering space and must be filled before a
        // deal) while keeping them below one reveal so the search digs rather
        // than hoards. No stock term: rewarding deals would make the planner
        // deal eagerly, the classic Spider blunder.
        return bankedCards * 20
            - hiddenCount * 25
            + emptyPiles * 10
            + descendingPairs
            + suitedRunBonus
            - breaks * 3
    }

    static func actions(from state: GameState) -> [PlannedAction] {
        let firstEmptyColumn = state.tableau.firstIndex(where: \.isEmpty)
        var actions: [PlannedAction] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                // Empty columns are interchangeable: searching a drop into every one
                // only multiplies column-permuted twins, so canonicalize to the first.
                // (Players can still drop on any empty column.)
                if case .tableau(let index) = destination,
                   state.tableau[index].isEmpty,
                   index != firstEmptyColumn {
                    continue
                }
                if isPointlessSameSuitUnbind(selection, destination: destination, in: state) {
                    continue
                }
                actions.append(.move(selection: selection, destination: destination))
            }
        }
        if SpiderGameRules.canDealFromStock(state: state) {
            actions.append(.stockDeal)
        }
        return actions
    }

    /// The legal move into the first empty column whose resulting position
    /// scores best; ties keep the first candidate for determinism.
    static func bestFill(in state: GameState) -> PlannedAction? {
        guard let emptyIndex = state.tableau.firstIndex(where: \.isEmpty) else { return nil }
        var best: (action: PlannedAction, score: Int)?
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            let destination = Destination.tableau(emptyIndex)
            guard AutoMoveAdvisor.legalDestinations(for: selection, in: state)
                .contains(destination) else {
                continue
            }
            let action = PlannedAction.move(selection: selection, destination: destination)
            guard let next = apply(action, to: state) else { continue }
            let nextScore = score(next)
            if best.map({ nextScore > $0.score }) ?? true {
                best = (action, nextScore)
            }
        }
        return best?.action
    }

    /// Pulling a run off a suited join to re-host it on another top of the same
    /// rank can never gain anything: nothing is revealed (the join's upper card
    /// still covers the pile) and any dig the re-host enables is available in
    /// one move by taking the joined run along — a suited join is itself
    /// movable. Empty-column drops stay searchable; parking a run there is how
    /// the planner frees a join's upper card when no landing rank exists.
    static func isPointlessSameSuitUnbind(
        _ selection: Selection,
        destination: Destination,
        in state: GameState
    ) -> Bool {
        guard case .tableau(let sourcePile, let sourceIndex) = selection.source,
              sourceIndex > 0 else {
            return false
        }
        guard case .tableau(let destinationIndex) = destination,
              let destinationTop = state.tableau[destinationIndex].last else {
            return false
        }
        let parent = state.tableau[sourcePile][sourceIndex - 1]
        guard parent.isFaceUp, let movingCard = selection.cards.first else { return false }
        guard parent.suit == movingCard.suit,
              parent.rank.rawValue == movingCard.rank.rawValue + 1 else {
            return false
        }
        return destinationTop.rank == parent.rank
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
            SpiderGameRules.resolveCompletedRuns(in: &nextState)
        case .stockDeal:
            guard SpiderGameRules.dealStockRow(in: &nextState) != nil else { return nil }
        }
        return nextState
    }

    /// FNV-1a over a canonical layout: tableau piles are sorted before mixing
    /// because Spider columns are strategically interchangeable, foundations
    /// collapse to per-suit banked-run counts (banked runs carry no order), and
    /// the stock contributes only its count (its order never changes within one
    /// game). Cards hash by content, so the twin cards of the two decks
    /// collapse identical positions to one visited entry.
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
