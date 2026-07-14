import Foundation

/// Bounded best-first hint planner for Canfield.
///
/// Searches sequences of real actions — whole-pile tableau moves, waste and
/// reserve plays, foundation builds, and stock taps — up to a node/time
/// budget, scoring positions by foundation cards, reserve cards freed,
/// developed stock/waste cards, and how deeply the next foundation-needed
/// cards are buried. `bestLine` returns the whole action sequence to the best
/// position found that strictly improves on the current one; `HintPlanner`
/// follows the cached line action by action: like Forty Thieves, every
/// Canfield tableau move is reversible until a card builds or the reserve
/// turns, so re-search after each move can oscillate between equally
/// attractive lines, while following one improving line ratchets the position
/// strictly forward.
///
/// The search reads the true state, including the face-down stock and reserve
/// order, but it only ever recommends actions that are legal right now.
/// Searching through stock taps is what lets the planner line up the plays a
/// buried stock card enables *before* recommending the tap; the tap itself is
/// score-neutral, so tap-crossing lines only win when the plays they enable
/// pay for them. Unlike Forty Thieves' single pass, a tap on the spent stock
/// recycles the waste, so taps alone can cycle back to an earlier position —
/// the visited set is what keeps searched lines loop-free, and an exhausted
/// search (recycles included) is a proof the position cannot progress at all.
/// Foundations are locked and `candidateSelections` offers no foundation
/// sources for rollback-free variants, so there is no rollback stage.
///
/// Measured over 500 seeded deals in the hint probe (the ledger in
/// `tools/hint-probe/README.md` is the regression baseline): following every
/// hint wins 25.0% of games versus the 1.2% random control, with zero
/// stalemate loops, zero exact-position revisits, and every loss an honest
/// deadlock proven by an exhaustive search.
nonisolated enum CanfieldPlanner {
    struct Limits {
        var maxNodes: Int
        var maxDepth: Int
        var deadline: Date?

        // Canfield branches modestly (six sources at most, few legal landings
        // each, plus the tap), but its lines cross many taps — a full pass
        // over the stock is a dozen — so it keeps Forty Thieves' node budget
        // with a deeper horizon.
        init(maxNodes: Int = 30_000, maxDepth: Int = 96, deadline: Date? = nil) {
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
        /// Nothing within the horizon improves on the current position. When
        /// the search ran out of reachable states — rather than nodes, depth,
        /// or time — that is proof the position cannot progress at all, since
        /// taps and recycles were searched too.
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
        // Recycling rebuilds the stock from whatever the waste held, so unlike
        // Forty Thieves the stock's count does not identify its contents — it
        // is spelled out in full, as is the waste. The reserve only ever
        // shrinks off its fixed dealt order, so its count is exact.
        for card in state.stock { append(card: card) }
        key.append("#\(state.reserve.count)~")
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
            guard !state.stock.isEmpty || !state.waste.isEmpty else { return nil }
            return .stockTap
        }
    }

    static func bestLine(in state: GameState, limits: Limits = Limits()) -> SearchOutcome {
        guard state.variant == .canfield else { return .noProgress(searchWasExhaustive: false) }
        return search(in: state, limits: limits)
    }

    /// Applies an action without re-validating legality: the planner only feeds
    /// in actions it just generated (the hint probe reuses this as the same
    /// pure logic the session performs), and revalidating each one there
    /// dominates search cost. Mirrors the session's move effects, including
    /// the compulsory reserve fill of an emptied pile.
    static func apply(_ action: PlannedAction, to state: GameState) -> GameState? {
        var nextState = state
        switch action {
        case .move(let selection, let destination):
            switch selection.source {
            case .tableau(let pile, let index):
                nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
                CanfieldGameRules.refillEmptyPileFromReserve(on: &nextState, pileIndex: pile)
            case .waste:
                _ = nextState.waste.popLast()
                nextState.wasteDrawCount = CanfieldGameRules.wasteDrawCountAfterWastePlay(in: nextState)
            case .reserve:
                _ = nextState.reserve.popLast()
                if let newTopIndex = nextState.reserve.indices.last {
                    nextState.reserve[newTopIndex].isFaceUp = true
                }
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
            if nextState.stock.isEmpty {
                // Mirrors the session: a tap on the spent stock turns the
                // waste over; the next tap draws.
                guard !nextState.waste.isEmpty else { return nil }
                nextState.stock = nextState.waste.reversed().map { card in
                    var newCard = card
                    newCard.isFaceUp = false
                    return newCard
                }
                nextState.waste.removeAll()
                nextState.wasteDrawCount = 0
            } else {
                let drawCount = min(CanfieldGameRules.stockDrawCount, nextState.stock.count)
                for _ in 0..<drawCount {
                    var card = nextState.stock.removeLast()
                    card.isFaceUp = true
                    nextState.waste.append(card)
                }
                nextState.wasteDrawCount = drawCount
            }
        }
        return nextState
    }
}

// MARK: - Search internals

nonisolated private extension CanfieldPlanner {
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
            // A line that builds a foundation card or frees a reserve card
            // and change is a solid hint; once one is in hand, cap how long
            // we keep hunting for something better.
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
        let foundationCards = state.foundations.reduce(0) { $0 + $1.count }
        let undevelopedCount = state.stock.count + state.waste.count
        // Foundation cards are the only permanent progress and set the scale.
        // Freeing a reserve card is the strategic heart of the game — each one
        // is a forced-order dig the deal owes — so it prices high but below a
        // foundation card, and the compulsory fill makes emptying a pile worth
        // exactly one freed reserve card. Developing cards out of the
        // stock/waste counts as progress (so a stock tap is score-neutral and
        // playing off the waste beats an equivalent tableau play), and each
        // card covering the next foundation-needed card of any suit is a dig
        // the line still owes.
        return foundationCards * 20
            - state.reserve.count * 8
            - undevelopedCount * 2
            - nextNeededBurialDepth(state) * 2
    }

    /// How many cards sit on top of the tableau copy of each foundation's
    /// next needed card, summed over the four foundations. Cards still in the
    /// stock, waste, or reserve owe no dig here — the undeveloped and reserve
    /// terms already carry them.
    static func nextNeededBurialDepth(_ state: GameState) -> Int {
        guard let base = CanfieldGameRules.baseRank(in: state) else { return 0 }
        var total = 0
        for suit in Suit.allCases {
            let height = state.foundations
                .first { $0.first?.suit == suit }?
                .count ?? 0
            guard height < Rank.allCases.count else { continue }
            let neededOffset = height
            for pile in state.tableau {
                for index in pile.indices
                where pile[index].suit == suit
                    && CanfieldGameRules.foundationOffset(of: pile[index].rank, from: base) == neededOffset {
                    total += pile.count - 1 - index
                }
            }
        }
        return total
    }

    static func actions(from state: GameState) -> [PlannedAction] {
        let firstEmptyColumn = state.tableau.firstIndex(where: \.isEmpty)
        var actions: [PlannedAction] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            // Exact-equivalence canonicalizations, all invisible to the player.
            var tookFoundation = false
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                switch destination {
                case .foundation:
                    // Only a base-rank card ever has more than one legal
                    // foundation — the empty piles are interchangeable — so
                    // keep the first.
                    if tookFoundation { continue }
                    tookFoundation = true
                case .tableau(let index):
                    // Empty columns are interchangeable: canonicalize to the
                    // first. (Players can still drop on any empty column.)
                    if state.tableau[index].isEmpty, index != firstEmptyColumn { continue }
                case .freeCell, .pyramid, .waste, .discard:
                    continue
                }
                actions.append(.move(selection: selection, destination: destination))
            }
        }
        if !state.stock.isEmpty || !state.waste.isEmpty {
            actions.append(.stockTap)
        }
        return actions
    }

    /// FNV-1a over a canonical layout: tableau piles are sorted before mixing
    /// because Canfield's four piles are strategically interchangeable, and
    /// foundations collapse to their per-suit heights (which pile holds which
    /// suit carries nothing; the heights plus the base rank determine their
    /// exact contents). The stock and waste are mixed in full — recycling
    /// rebuilds the stock from the waste, so neither is derivable from a
    /// count — while the reserve only ever shrinks off its fixed dealt order,
    /// so its count is exact.
    static func stateHash(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) {
            hash = (hash ^ UInt64(value)) &* 0x100000001b3
        }
        func encode(card: Card) -> UInt8 {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            return UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0))
        }
        for card in state.stock { mix(encode(card: card)) }
        mix(0xFC)
        for card in state.waste { mix(encode(card: card)) }
        mix(0xFB)
        mix(UInt8(state.reserve.count))
        for suit in Suit.allCases {
            mix(0xFE)
            let height = state.foundations
                .first { $0.first?.suit == suit }?
                .count ?? 0
            mix(UInt8(height))
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
