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
        let result = search(
            from: state,
            stockDrawCount: stockDrawCount,
            rootScore: rootScore,
            limits: limits
        )
        guard let best = result.best else { return nil }
        return firstAction(leadingTo: best.index, nodes: result.nodes)
    }
}

// MARK: - Search internals

private extension KlondikePlanner {
    struct BestNode {
        let index: Int
        let score: Int
        let depth: Int

        func isBetter(than other: BestNode?) -> Bool {
            guard let other else { return true }
            return score > other.score || (score == other.score && depth < other.depth)
        }
    }

    struct SearchResult {
        let nodes: [Node]
        let best: BestNode?
    }

    struct SearchStorage {
        var nodes: [Node]
        var visited: Set<UInt64>
        var heap: Heap
        var order: Int
    }

    static func search(
        from state: GameState,
        stockDrawCount: Int,
        rootScore: Int,
        limits: Limits
    ) -> SearchResult {
        let rootNode = Node(state: state, parent: -1, action: nil, depth: 0, score: rootScore)
        var heap = Heap()
        heap.push(HeapEntry(priority: rootScore, order: 0, index: 0))
        var storage = SearchStorage(
            nodes: [rootNode],
            visited: [stateHash(state)],
            heap: heap,
            order: 0
        )
        var expansions = 0
        var best: BestNode?

        while let entry = storage.heap.pop() {
            let nodeIndex = entry.index
            let node = storage.nodes[nodeIndex]

            if node.score > rootScore {
                let candidate = BestNode(index: nodeIndex, score: node.score, depth: node.depth)
                if candidate.isBetter(than: best) {
                    best = candidate
                }
                if isWon(node.state) { break }
            }

            guard node.depth < limits.maxDepth else { continue }
            expansions += 1
            if shouldStop(
                nodeCount: storage.nodes.count,
                expansions: expansions,
                best: best,
                rootScore: rootScore,
                limits: limits
            ) { break }
            appendChildren(
                of: node,
                nodeIndex: nodeIndex,
                stockDrawCount: stockDrawCount,
                storage: &storage
            )
        }
        return SearchResult(nodes: storage.nodes, best: best)
    }

    static func shouldStop(
        nodeCount: Int,
        expansions: Int,
        best: BestNode?,
        rootScore: Int,
        limits: Limits
    ) -> Bool {
        if nodeCount >= limits.maxNodes { return true }
        if expansions % 64 == 0, let deadline = limits.deadline, Date() > deadline { return true }
        return best.map { $0.score - rootScore >= 20 && expansions >= 768 } ?? false
    }

    static func appendChildren(
        of node: Node,
        nodeIndex: Int,
        stockDrawCount: Int,
        storage: inout SearchStorage
    ) {
        for action in actions(from: node.state, stockDrawCount: stockDrawCount) {
            guard let nextState = apply(action, to: node.state, stockDrawCount: stockDrawCount),
                  storage.visited.insert(stateHash(nextState)).inserted else { continue }
            let nextScore = score(nextState)
            storage.nodes.append(
                Node(
                    state: nextState,
                    parent: nodeIndex,
                    action: action,
                    depth: node.depth + 1,
                    score: nextScore
                )
            )
            storage.order += 1
            storage.heap.push(
                HeapEntry(
                    priority: nextScore * 4 - (node.depth + 1),
                    order: storage.order,
                    index: storage.nodes.count - 1
                )
            )
        }
    }

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

    struct HeapEntry {
        let priority: Int
        let order: Int
        let index: Int

        func takesPriority(over other: HeapEntry) -> Bool {
            priority != other.priority ? priority > other.priority : order < other.order
        }
    }

    struct Heap {
        private var entries: [HeapEntry] = []

        mutating func push(_ entry: HeapEntry) {
            entries.append(entry)
            var child = entries.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard entries[child].takesPriority(over: entries[parent]) else { break }
                entries.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> HeapEntry? {
            guard let top = entries.first else { return nil }
            let last = entries.removeLast()
            if !entries.isEmpty {
                entries[0] = last
                var parent = 0
                while true {
                    let left = parent * 2 + 1
                    let right = left + 1
                    var candidate = parent
                    if left < entries.count, entries[left].takesPriority(over: entries[candidate]) {
                        candidate = left
                    }
                    if right < entries.count, entries[right].takesPriority(over: entries[candidate]) {
                        candidate = right
                    }
                    guard candidate != parent else { break }
                    entries.swapAt(parent, candidate)
                    parent = candidate
                }
            }
            return top
        }
    }

    static func isWon(_ state: GameState) -> Bool {
        state.foundations.allSatisfy { $0.count == Rank.allCases.count }
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
            remove(selection, from: &nextState, stockDrawCount: stockDrawCount)
            guard append(selection.cards, to: destination, in: &nextState) else { return nil }
            return nextState
        case .stockTap:
            return stockTapState(from: state, stockDrawCount: stockDrawCount)
        }
    }

    static func remove(_ selection: Selection, from state: inout GameState, stockDrawCount: Int) {
        switch selection.source {
        case .waste:
            _ = state.waste.popLast()
            state.wasteDrawCount = stockDrawCount == DrawMode.one.rawValue
                ? min(1, state.waste.count)
                : max(0, state.wasteDrawCount - 1)
        case .freeCell(let slot):
            state.freeCells[slot] = nil
        case .foundation(let pile):
            _ = state.foundations[pile].popLast()
        case .tableau(let pile, let index):
            state.tableau[pile].removeSubrange(index..<state.tableau[pile].count)
            if let topIndex = state.tableau[pile].indices.last, !state.tableau[pile][topIndex].isFaceUp {
                state.tableau[pile][topIndex].isFaceUp = true
            }
        }
    }

    static func append(_ cards: [Card], to destination: Destination, in state: inout GameState) -> Bool {
        switch destination {
        case .foundation(let index):
            guard cards.count == 1, let card = cards.first else { return false }
            state.foundations[index].append(card)
        case .tableau(let index):
            state.tableau[index].append(contentsOf: cards)
        case .freeCell(let index):
            guard cards.count == 1, let card = cards.first else { return false }
            state.freeCells[index] = card
        }
        return true
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
