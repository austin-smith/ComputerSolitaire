import Foundation

/// Bounded best-first hint planner for Klondike.
///
/// Searches sequences of real moves and stock taps up to a node/time budget, scoring
/// positions by foundation progress, revealed cards, and open columns. The hint is the
/// first action of the best line found that strictly improves on the current position;
/// nil means nothing within the horizon makes progress (the game is stuck or lost).
///
/// The search reads the true state, including cards the player hasn't seen yet, but it
/// only ever recommends actions that are legal right now.
enum KlondikePlanner {
    struct Limits {
        var maxNodes: Int
        var maxDepth: Int
        var deadline: Date?

        init(maxNodes: Int = 8_000, maxDepth: Int = 40, deadline: Date? = nil) {
            self.maxNodes = maxNodes
            self.maxDepth = maxDepth
            self.deadline = deadline
        }
    }

    static func bestHint(
        in state: GameState,
        stockDrawCount: Int,
        limits: Limits = Limits()
    ) -> HintAdvisor.Hint? {
        guard state.variant == .klondike else { return nil }

        let rootScore = score(state)
        var nodes: [Node] = [Node(state: state, parent: -1, action: nil, depth: 0, score: rootScore)]
        var visited: Set<UInt64> = [stateHash(state)]
        var heap = BinaryHeap<HeapEntry>()
        heap.push(HeapEntry(priority: rootScore, order: 0, index: 0))
        var order = 0
        var expansions = 0
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

            guard node.depth < limits.maxDepth else { continue }
            expansions += 1
            if nodes.count >= limits.maxNodes { break }
            if expansions % 64 == 0, let deadline = limits.deadline, Date() > deadline {
                break
            }
            // A line that reveals a card or banks a foundation card is a solid hint;
            // once one is in hand, cap how long we keep hunting for something better.
            if let best, best.score - rootScore >= 20, expansions >= 768 {
                break
            }

            for action in actions(from: node.state, stockDrawCount: stockDrawCount) {
                guard let nextState = apply(action, to: node.state, stockDrawCount: stockDrawCount) else {
                    continue
                }
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

        guard let best else { return nil }
        return firstAction(leadingTo: best.index, nodes: nodes)
    }
}

// MARK: - Search internals

private extension KlondikePlanner {
    enum Action {
        case move(Selection, Destination)
        case stockTap
    }

    struct Node {
        let state: GameState
        let parent: Int
        let action: Action?
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
        for pile in state.tableau {
            if pile.isEmpty { emptyPiles += 1 }
            for card in pile where !card.isFaceUp { hiddenCount += 1 }
        }
        let foundationCount = state.foundations.reduce(0) { $0 + $1.count }
        let undevelopedCount = state.stock.count + state.waste.count
        // Developing cards out of the stock/waste cycle counts as progress too, so
        // waste-to-tableau lines rank above pure reshuffles.
        return foundationCount * 20 - hiddenCount * 25 + emptyPiles * 4 - undevelopedCount * 2
    }

    static func actions(from state: GameState, stockDrawCount: Int) -> [Action] {
        var actions: [Action] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            // Foundation rollbacks explode the branching factor for marginal benefit.
            if case .foundation = selection.source { continue }
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                actions.append(.move(selection, destination))
            }
        }
        if !state.stock.isEmpty || !state.waste.isEmpty {
            actions.append(.stockTap)
        }
        return actions
    }

    /// Applies an action without re-validating legality: the planner only feeds in
    /// actions it just generated from `legalDestinations`, and revalidating each one
    /// there dominates search cost. Mirrors the session's move effects.
    static func apply(_ action: Action, to state: GameState, stockDrawCount: Int) -> GameState? {
        switch action {
        case .move(let selection, let destination):
            var nextState = state
            switch selection.source {
            case .waste:
                _ = nextState.waste.popLast()
                if stockDrawCount == DrawMode.one.rawValue {
                    nextState.wasteDrawCount = min(1, nextState.waste.count)
                } else {
                    nextState.wasteDrawCount = max(0, nextState.wasteDrawCount - 1)
                }
            case .freeCell(let slot):
                nextState.freeCells[slot] = nil
            case .foundation(let pile):
                _ = nextState.foundations[pile].popLast()
            case .tableau(let pile, let index):
                nextState.tableau[pile].removeSubrange(index..<nextState.tableau[pile].count)
                if let topIndex = nextState.tableau[pile].indices.last,
                   !nextState.tableau[pile][topIndex].isFaceUp {
                    nextState.tableau[pile][topIndex].isFaceUp = true
                }
            case .pyramid, .triPeaks, .reserve:
                // Unreachable: this planner only searches Klondike states.
                return nil
            }
            switch destination {
            case .foundation(let index):
                guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
                nextState.foundations[index].append(card)
            case .tableau(let index):
                nextState.tableau[index].append(contentsOf: selection.cards)
            case .freeCell(let index):
                guard selection.cards.count == 1, let card = selection.cards.first else { return nil }
                nextState.freeCells[index] = card
            case .pyramid, .waste, .discard:
                // Unreachable: this planner only searches Klondike states.
                return nil
            }
            return nextState
        case .stockTap:
            return stockTapState(from: state, stockDrawCount: stockDrawCount)
        }
    }

    /// Mirrors drawFromStock / recycleWaste in the session.
    static func stockTapState(from state: GameState, stockDrawCount: Int) -> GameState? {
        var nextState = state

        if !nextState.stock.isEmpty {
            let drawCount = min(max(1, stockDrawCount), nextState.stock.count)
            for _ in 0..<drawCount {
                var card = nextState.stock.removeLast()
                card.isFaceUp = true
                nextState.waste.append(card)
            }
            nextState.wasteDrawCount = drawCount
            return nextState
        }

        guard !nextState.waste.isEmpty else { return nil }
        nextState.stock = nextState.waste.reversed().map { card in
            var recycledCard = card
            recycledCard.isFaceUp = false
            return recycledCard
        }
        nextState.waste.removeAll()
        nextState.wasteDrawCount = 0
        return nextState
    }

    /// FNV-1a over the full layout. A 64-bit collision inside one search's visited set
    /// (a few thousand entries) is vanishingly unlikely and merely prunes one line.
    static func stateHash(_ state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ value: UInt8) {
            hash = (hash ^ UInt64(value)) &* 0x100000001b3
        }
        func mix(card: Card) {
            let suitValue = Suit.allCases.firstIndex(of: card.suit) ?? 0
            mix(UInt8(suitValue << 5 | card.rank.rawValue << 1 | (card.isFaceUp ? 1 : 0)))
        }
        for card in state.stock { mix(card: card) }
        mix(0xFF)
        for card in state.waste { mix(card: card) }
        mix(UInt8(min(255, max(0, state.wasteDrawCount))))
        for pile in state.foundations {
            mix(0xFE)
            for card in pile { mix(card: card) }
        }
        for pile in state.tableau {
            mix(0xFD)
            for card in pile { mix(card: card) }
        }
        return hash
    }

    static func firstAction(leadingTo index: Int, nodes: [Node]) -> HintAdvisor.Hint? {
        var cursor = index
        var action: Action?
        while cursor >= 0, nodes[cursor].parent >= 0 {
            action = nodes[cursor].action
            cursor = nodes[cursor].parent
        }
        switch action {
        case .move(let selection, let destination):
            return .move(HintAdvisor.HintMove(selection: selection, destination: destination))
        case .stockTap:
            return .stockTap
        case nil:
            return nil
        }
    }
}
