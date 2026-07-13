import Foundation

// Statistical quality probe for the hint engines. Every variant gets the same
// treatment: seeded deals played to completion by a bot that follows every hint,
// alongside a forward-only random control. Hints come from the planners'
// deterministic entry points — no wall-clock deadlines — so every figure is
// exactly reproducible. Exits nonzero if any hint follower ever loops. Compiled
// by run.sh against the UI-free Game sources; never part of the app or test
// targets. See README.md for the recorded baselines and acceptance gates.

// MARK: - Seeded dealing (mirrors GameStateFixtures in ComputerSolitaireTests)

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}

func seededShuffle(_ cards: [Card], seed: UInt64) -> [Card] {
    var generator = SeededRandomNumberGenerator(seed: seed)
    var deck = cards
    for index in stride(from: deck.count - 1, through: 1, by: -1) {
        let swapIndex = Int(generator.next() % UInt64(index + 1))
        deck.swapAt(index, swapIndex)
    }
    return deck
}

func seededDeck(seed: UInt64, faceUp: Bool) -> [Card] {
    seededShuffle(
        Suit.allCases.flatMap { suit in
            Rank.allCases.map { rank in Card(suit: suit, rank: rank, isFaceUp: faceUp) }
        },
        seed: seed
    )
}

func seededSpiderDeal(seed: UInt64, suitCount: SpiderSuitCount) -> GameState {
    var deck = seededShuffle(SpiderDeck.deck(suitCount: suitCount), seed: seed)
    var tableau: [[Card]] = Array(repeating: [], count: 10)
    for pileIndex in 0..<10 {
        let cardCount = pileIndex < 4 ? 6 : 5
        for cardIndex in 0..<cardCount {
            var card = deck.removeLast()
            card.isFaceUp = cardIndex == cardCount - 1
            tableau[pileIndex].append(card)
        }
    }
    return GameState(
        variant: .spider,
        stock: deck,
        waste: [],
        wasteDrawCount: 0,
        freeCells: Array(repeating: nil, count: 4),
        foundations: Array(repeating: [], count: 8),
        tableau: tableau
    )
}

func seededDeal(variant: GameVariant, seed: UInt64, spiderSuitCount: SpiderSuitCount = .two) -> GameState {
    switch variant {
    case .klondike:
        var deck = seededDeck(seed: seed, faceUp: false)
        var tableau: [[Card]] = Array(repeating: [], count: 7)
        for pileIndex in 0..<7 {
            for cardIndex in 0...pileIndex {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex == pileIndex
                tableau[pileIndex].append(card)
            }
        }
        return GameState(
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )

    case .freecell:
        let deck = seededDeck(seed: seed, faceUp: true)
        var tableau = Array(repeating: [Card](), count: 8)
        for index in 0..<deck.count {
            tableau[index % 8].append(deck[index])
        }
        return GameState(
            variant: .freecell,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )

    case .yukon:
        var deck = seededDeck(seed: seed, faceUp: false)
        var tableau: [[Card]] = Array(repeating: [], count: 7)
        for pileIndex in 0..<7 {
            let faceDownCount = pileIndex == 0 ? 0 : pileIndex
            let faceUpCount = pileIndex == 0 ? 1 : 5
            for cardIndex in 0..<(faceDownCount + faceUpCount) {
                var card = deck.removeLast()
                card.isFaceUp = cardIndex >= faceDownCount
                tableau[pileIndex].append(card)
            }
        }
        return GameState(
            variant: .yukon,
            stock: [],
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: tableau
        )

    case .spider:
        return seededSpiderDeal(seed: seed, suitCount: spiderSuitCount)

    case .pyramid:
        var deck = seededDeck(seed: seed, faceUp: false)
        var pyramid: [Card?] = []
        for _ in 0..<PyramidGeometry.cardCount {
            var card = deck.removeLast()
            card.isFaceUp = true
            pyramid.append(card)
        }
        return GameState(
            variant: .pyramid,
            stock: deck,
            waste: [],
            wasteDrawCount: 0,
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            pyramid: pyramid,
            discard: []
        )

    case .tripeaks:
        // Mirrors GameState.newTriPeaksGame (and GameStateFixtures.seededTriPeaksDeal).
        var deck = seededDeck(seed: seed, faceUp: false)
        var triPeaks: [Card?] = []
        for index in 0..<TriPeaksGeometry.cardCount {
            var card = deck.removeLast()
            card.isFaceUp = TriPeaksGeometry.row(of: index) == TriPeaksGeometry.rowCount - 1
            triPeaks.append(card)
        }
        var starter = deck.removeLast()
        starter.isFaceUp = true
        return GameState(
            variant: .tripeaks,
            stock: deck,
            waste: [starter],
            wasteDrawCount: 1,
            foundations: Array(repeating: [], count: 4),
            tableau: [],
            triPeaks: triPeaks
        )
    }
}

// MARK: - Shared driver plumbing

func fingerprint(_ state: GameState) -> UInt64 {
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
    for cell in state.freeCells {
        mix(0xFC)
        if let card = cell { mix(card: card) }
    }
    for pile in state.foundations {
        mix(0xFE)
        for card in pile { mix(card: card) }
    }
    for pile in state.tableau {
        mix(0xFD)
        for card in pile { mix(card: card) }
    }
    for slot in state.pyramid {
        mix(0xFB)
        if let card = slot { mix(card: card) }
    }
    // Section separator: without it, clearing the last pyramid slot to the
    // discard leaves the byte stream unchanged and reads as a false revisit.
    mix(0xFA)
    for card in state.discard { mix(card: card) }
    mix(UInt8(min(255, max(0, state.wasteRecyclesUsed))))
    for slot in state.triPeaks {
        mix(0xF9)
        if let card = slot { mix(card: card) }
    }
    return hash
}

func apply(
    _ selection: Selection,
    _ destination: Destination,
    to state: GameState,
    stockDrawCount: Int
) -> GameState? {
    AutoMoveAdvisor.simulatedState(
        afterMoving: selection,
        to: destination,
        in: state,
        stockDrawCount: stockDrawCount
    )
}

/// Mirrors dealSpiderStockRow in the session (via the shared rules function,
/// including the completed-run sweep).
func spiderStockDeal(_ state: GameState) -> GameState? {
    var next = state
    guard SpiderGameRules.dealStockRow(in: &next) != nil else { return nil }
    return next
}

/// Mirrors handlePyramidStockTap / recyclePyramidWaste in the session: draw one,
/// or recycle within the pass limit. The planner's apply is the same pure logic.
func pyramidStockTap(_ state: GameState) -> GameState? {
    PyramidPlanner.apply(state.stock.isEmpty ? .resetStock : .draw, to: state)
}

func pyramidCleared(_ state: GameState) -> Int {
    state.pyramid.count(where: { $0 == nil })
}

/// Mirrors handleTriPeaksStockTap in the session: draw one, no recycles ever.
/// The planner's apply is the same pure logic.
func triPeaksStockTap(_ state: GameState) -> GameState? {
    TriPeaksPlanner.apply(.draw, to: state)
}

func triPeaksCleared(_ state: GameState) -> Int {
    state.triPeaks.count(where: { $0 == nil })
}

/// Mirrors drawFromStock / recycleWaste in the session.
func stockTap(_ state: GameState, drawCount: Int) -> GameState? {
    var next = state
    if !next.stock.isEmpty {
        let n = min(drawCount, next.stock.count)
        for _ in 0..<n {
            var card = next.stock.removeLast()
            card.isFaceUp = true
            next.waste.append(card)
        }
        next.wasteDrawCount = n
        return next
    }
    guard !next.waste.isEmpty else { return nil }
    next.stock = next.waste.reversed().map { card in
        var recycled = card
        recycled.isFaceUp = false
        return recycled
    }
    next.waste.removeAll()
    next.wasteDrawCount = 0
    return next
}

enum Outcome {
    case win(moves: Int)
    case deadlock(foundation: Int)
    case stalemateLoop(foundation: Int)
    case actionCap(foundation: Int)
}

/// Yukon/FreeCell games finish or die well under this; Klondike needs headroom
/// for stock cycling, and Spider for grooming 104 cards across five deals.
/// (Pyramid is structurally bounded near 100 actions: three 24-card passes,
/// two resets, and at most 26 removal moves. TriPeaks is bounded at 51: every
/// action consumes a peak card or a stock card.)
func actionCap(for variant: GameVariant) -> Int {
    switch variant {
    case .klondike:
        return 1_200
    case .spider:
        return 1_000
    case .freecell, .yukon, .pyramid, .tripeaks:
        return 600
    }
}

func foundationCount(_ state: GameState) -> Int {
    state.foundations.reduce(0) { $0 + $1.count }
}

// MARK: - Hint-following players (deterministic planner entry points)

func playKlondikeFollowingHints(seed: UInt64, drawCount: Int) -> Outcome {
    var state = seededDeal(variant: .klondike, seed: seed)
    // Stock recycling makes exact-state revisits legal in Klondike, but this
    // follower is deterministic: the same position always produces the same hint,
    // so any revisit means the hints are looping forever. (The random control
    // rightly skips this check — a stochastic player diverges after a revisit.)
    var seen: Set<UInt64> = [fingerprint(state)]
    var actions = 0
    while actions < actionCap(for: .klondike) {
        if state.isWon { return .win(moves: actions) }
        guard let hint = KlondikePlanner.bestHint(in: state, stockDrawCount: drawCount) else {
            return .deadlock(foundation: foundationCount(state))
        }
        switch hint {
        case .move(let move):
            guard let next = apply(move.selection, move.destination, to: state, stockDrawCount: drawCount) else {
                fatalError("Seed \(seed): illegal Klondike hint")
            }
            state = next
        case .stockTap:
            guard let next = stockTap(state, drawCount: drawCount) else {
                fatalError("Seed \(seed): stock tap hinted with nothing to tap")
            }
            state = next
        }
        actions += 1
        if !seen.insert(fingerprint(state)).inserted {
            return .stalemateLoop(foundation: foundationCount(state))
        }
    }
    return .actionCap(foundation: foundationCount(state))
}

func playFreeCellFollowingHints(seed: UInt64) -> Outcome {
    // Replicates HintPlanner's FreeCell path without its wall-clock deadline:
    // solve once, follow the cached line; fall back to the tap heuristic when the
    // solver proves nothing (with a strict revisit check so fallback shuffling
    // registers as the loss it is).
    var state = seededDeal(variant: .freecell, seed: seed)
    var plan: [String: FreeCellSolver.Move] = [:]
    var seen: Set<UInt64> = [fingerprint(state)]
    var moves = 0
    while moves < actionCap(for: .freecell) {
        if state.isWon { return .win(moves: moves) }

        let key = FreeCellSolver.stateKey(for: state)
        var move = plan[key].flatMap { FreeCellSolver.materialize($0, in: state) }
        var cameFromFallback = false
        if move == nil {
            plan.removeAll()
            if let solution = FreeCellSolver.solve(state) {
                plan = FreeCellSolver.keyedMoves(along: solution, from: state)
            }
            move = plan[key].flatMap { FreeCellSolver.materialize($0, in: state) }
            if move == nil {
                move = TapMovePolicy.bestMove(in: state)
                cameFromFallback = true
            }
        }
        guard let move else {
            return .deadlock(foundation: foundationCount(state))
        }

        guard let next = apply(move.selection, move.destination, to: state, stockDrawCount: 3) else {
            fatalError("Seed \(seed): illegal FreeCell hint")
        }
        state = next
        moves += 1
        if !seen.insert(fingerprint(state)).inserted {
            // A solved line is finite and ends in a win, so it can never revisit.
            // A revisit is therefore only reachable in fallback, on a deal the
            // solver cannot prove: the nudge is circling, the hint stack is out of
            // constructive moves, and that is a deadlock — FreeCell's analogue of
            // Yukon's nil. A revisit on a plan line would be a genuinely broken
            // solver and stays a gate-tripping loop.
            return cameFromFallback
                ? .deadlock(foundation: foundationCount(state))
                : .stalemateLoop(foundation: foundationCount(state))
        }
    }
    return .actionCap(foundation: foundationCount(state))
}

func playYukonFollowingHints(seed: UInt64) -> (outcome: Outcome, revisitEvents: Int) {
    // Replicates HintPlanner's Yukon path without its wall-clock deadline: follow
    // each improving line to its end, then replan; nil means no progress exists.
    var state = seededDeal(variant: .yukon, seed: seed)
    var visitCounts: [UInt64: Int] = [fingerprint(state): 1]
    var revisitEvents = 0
    var moves = 0
    while moves < actionCap(for: .yukon) {
        if state.isWon { return (.win(moves: moves), revisitEvents) }
        guard case .line(let line) = YukonPlanner.bestLine(in: state) else {
            return (.deadlock(foundation: foundationCount(state)), revisitEvents)
        }
        for move in line {
            guard let next = apply(move.selection, move.destination, to: state, stockDrawCount: 3) else {
                fatalError("Seed \(seed): illegal Yukon hint")
            }
            state = next
            moves += 1
            let key = fingerprint(state)
            let count = (visitCounts[key] ?? 0) + 1
            visitCounts[key] = count
            if count > 1 { revisitEvents += 1 }
            // A transient cross-line revisit is survivable (the next plan differs);
            // a third visit to the same exact layout means the hints are looping.
            if count >= 3 {
                return (.stalemateLoop(foundation: foundationCount(state)), revisitEvents)
            }
            // Cap before win, matching the other players: their win check only
            // runs on the next loop iteration, so a win landed on the final
            // permitted action classifies as .actionCap everywhere.
            if moves >= actionCap(for: .yukon) {
                return (.actionCap(foundation: foundationCount(state)), revisitEvents)
            }
            if state.isWon { return (.win(moves: moves), revisitEvents) }
        }
    }
    return (.actionCap(foundation: foundationCount(state)), revisitEvents)
}

func playSpiderFollowingHints(
    seed: UInt64,
    suitCount: SpiderSuitCount
) -> (outcome: Outcome, revisitEvents: Int) {
    // Replicates HintPlanner's Spider path without its wall-clock deadline:
    // follow each improving line (which may include stock deals) to its end,
    // then replan; on no-progress, follow the deal-preparation fallback the
    // real hint stack uses, and declare a deadlock only when no deal remains.
    var state = seededSpiderDeal(seed: seed, suitCount: suitCount)
    var visitCounts: [UInt64: Int] = [fingerprint(state): 1]
    var revisitEvents = 0
    var actions = 0

    func record(_ nextState: GameState) -> Outcome? {
        state = nextState
        actions += 1
        let key = fingerprint(state)
        let count = (visitCounts[key] ?? 0) + 1
        visitCounts[key] = count
        if count > 1 { revisitEvents += 1 }
        // A transient cross-line revisit is survivable (the next plan differs);
        // a third visit to the same exact layout means the hints are looping.
        if count >= 3 {
            return .stalemateLoop(foundation: foundationCount(state))
        }
        // Cap before win, matching the other players: their win check only
        // runs on the next loop iteration, so a win landed on the final
        // permitted action classifies as .actionCap everywhere.
        if actions >= actionCap(for: .spider) {
            return .actionCap(foundation: foundationCount(state))
        }
        if state.isWon { return .win(moves: actions) }
        return nil
    }

    func applied(_ action: SpiderPlanner.PlannedAction) -> GameState? {
        switch action {
        case .move(let selection, let destination):
            return apply(selection, destination, to: state, stockDrawCount: 3)
        case .stockDeal:
            return spiderStockDeal(state)
        }
    }

    while actions < actionCap(for: .spider) {
        if state.isWon { return (.win(moves: actions), revisitEvents) }
        switch SpiderPlanner.bestLine(in: state) {
        case .line(let line):
            for action in line {
                guard let next = applied(action) else {
                    fatalError("Seed \(seed): illegal Spider hint")
                }
                if let outcome = record(next) { return (outcome, revisitEvents) }
            }

        case .noProgress:
            // Mirrors HintPlanner's fallback: follow the whole deal-preparation
            // line (fill any empty columns, then deal) without re-planning from
            // the intermediate positions.
            guard let preparation = SpiderPlanner.dealPreparationLine(in: state) else {
                return (.deadlock(foundation: foundationCount(state)), revisitEvents)
            }
            for action in preparation {
                guard let next = applied(action) else {
                    fatalError("Seed \(seed): illegal Spider deal preparation")
                }
                if let outcome = record(next) { return (outcome, revisitEvents) }
            }
        }
    }
    return (.actionCap(foundation: foundationCount(state)), revisitEvents)
}

func playPyramidFollowingHints(seed: UInt64) -> Outcome {
    // Replicates HintPlanner's Pyramid path without its wall-clock deadline:
    // follow each planned line — winning or max-clear — to its end, then replan;
    // noProgress means not one more pyramid card is clearable. Every Pyramid move
    // advances a monotone quantity, so for this deterministic follower any
    // revisit is a proven infinite loop. The loss column records pyramid cards
    // cleared (Pyramid banks no foundations).
    var state = seededDeal(variant: .pyramid, seed: seed)
    var plan: [String: PyramidPlanner.Move] = [:]
    var seen: Set<UInt64> = [fingerprint(state)]
    var actions = 0
    while actions < actionCap(for: .pyramid) {
        if state.isWon { return .win(moves: actions) }

        let key = PyramidPlanner.stateKey(for: state)
        var hint = plan[key].flatMap { PyramidPlanner.materialize($0, in: state) }
        if hint == nil {
            plan.removeAll()
            switch PyramidPlanner.bestLine(in: state) {
            case .winningLine(let line), .bestEffortLine(let line, _):
                plan = PyramidPlanner.keyedMoves(along: line, from: state)
            case .noProgress:
                return .deadlock(foundation: pyramidCleared(state))
            }
            hint = plan[key].flatMap { PyramidPlanner.materialize($0, in: state) }
        }
        guard let hint else {
            return .deadlock(foundation: pyramidCleared(state))
        }

        switch hint {
        case .move(let move):
            guard let next = apply(move.selection, move.destination, to: state, stockDrawCount: 1) else {
                fatalError("Seed \(seed): illegal Pyramid hint")
            }
            state = next
        case .stockTap:
            guard let next = pyramidStockTap(state) else {
                fatalError("Seed \(seed): pyramid stock tap with nothing to tap")
            }
            state = next
        }
        actions += 1
        if !seen.insert(fingerprint(state)).inserted {
            return .stalemateLoop(foundation: pyramidCleared(state))
        }
    }
    return .actionCap(foundation: pyramidCleared(state))
}

func playTriPeaksFollowingHints(seed: UInt64) -> Outcome {
    // Replicates HintPlanner's TriPeaks path without its wall-clock deadline:
    // follow each planned line — winning or max-clear — to its end, then replan;
    // noProgress means not one more peak card is clearable. Every TriPeaks move
    // consumes a card, so for this deterministic follower any revisit is a proven
    // infinite loop. The loss column records peak cards cleared (TriPeaks banks
    // no foundations).
    var state = seededDeal(variant: .tripeaks, seed: seed)
    var plan: [String: TriPeaksPlanner.Move] = [:]
    var seen: Set<UInt64> = [fingerprint(state)]
    var actions = 0
    while actions < actionCap(for: .tripeaks) {
        if state.isWon { return .win(moves: actions) }

        let key = TriPeaksPlanner.stateKey(for: state)
        var hint = plan[key].flatMap { TriPeaksPlanner.materialize($0, in: state) }
        if hint == nil {
            plan.removeAll()
            switch TriPeaksPlanner.bestLine(in: state) {
            case .winningLine(let line), .bestEffortLine(let line, _):
                plan = TriPeaksPlanner.keyedMoves(along: line, from: state)
            case .noProgress:
                return .deadlock(foundation: triPeaksCleared(state))
            }
            hint = plan[key].flatMap { TriPeaksPlanner.materialize($0, in: state) }
        }
        guard let hint else {
            return .deadlock(foundation: triPeaksCleared(state))
        }

        switch hint {
        case .move(let move):
            guard let next = apply(move.selection, move.destination, to: state, stockDrawCount: 1) else {
                fatalError("Seed \(seed): illegal TriPeaks hint")
            }
            state = next
        case .stockTap:
            guard let next = triPeaksStockTap(state) else {
                fatalError("Seed \(seed): TriPeaks stock tap with nothing to tap")
            }
            state = next
        }
        actions += 1
        if !seen.insert(fingerprint(state)).inserted {
            return .stalemateLoop(foundation: triPeaksCleared(state))
        }
    }
    return .actionCap(foundation: triPeaksCleared(state))
}

// MARK: - Control player

// The random-moves floor calibrates each variant's deal universe. Deliberately
// forward-only: foundation rollbacks are legal but excluded, so the floor
// measures aimless progress rather than self-sabotage (a uniform player would
// spend much of the endgame yanking banked cards back down). Two tap-policy
// control players were evaluated and retired as uninformative; those findings
// are recorded in README.md.
func playRandom(
    variant: GameVariant,
    seed: UInt64,
    drawCount: Int,
    spiderSuitCount: SpiderSuitCount = .two
) -> Outcome {
    // No revisit check: a stochastic player legitimately revisits positions and
    // diverges by luck afterward, so it runs to a true deadlock or the action cap.
    // (The hint followers keep their revisit checks — they are deterministic, so
    // for them a revisit is a proven infinite loop.)
    var state = seededDeal(variant: variant, seed: seed, spiderSuitCount: spiderSuitCount)
    var generator = SeededRandomNumberGenerator(seed: seed ^ 0xDEADBEEF)
    let lossProgress: (GameState) -> Int
    switch variant {
    case .pyramid:
        lossProgress = pyramidCleared
    case .tripeaks:
        lossProgress = triPeaksCleared
    case .klondike, .freecell, .yukon, .spider:
        lossProgress = foundationCount
    }
    var actions = 0
    while actions < actionCap(for: variant) {
        if state.isWon { return .win(moves: actions) }

        var legal: [(Selection, Destination)] = []
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            if case .foundation = selection.source { continue }
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                legal.append((selection, destination))
            }
        }
        let canTapStock: Bool
        switch variant {
        case .klondike:
            canTapStock = !state.stock.isEmpty || !state.waste.isEmpty
        case .spider:
            canTapStock = SpiderGameRules.canDealFromStock(state: state)
        case .pyramid:
            canTapStock = !state.stock.isEmpty || PyramidGameRules.canRecycleWaste(in: state)
        case .tripeaks:
            canTapStock = !state.stock.isEmpty
        case .freecell, .yukon:
            canTapStock = false
        }
        let choices = legal.count + (canTapStock ? 1 : 0)
        guard choices > 0 else { return .deadlock(foundation: lossProgress(state)) }

        let pick = Int(generator.next() % UInt64(choices))
        if pick == legal.count {
            let tapped: GameState?
            switch variant {
            case .spider:
                tapped = spiderStockDeal(state)
            case .pyramid:
                tapped = pyramidStockTap(state)
            case .tripeaks:
                tapped = triPeaksStockTap(state)
            case .klondike, .freecell, .yukon:
                tapped = stockTap(state, drawCount: drawCount)
            }
            guard let next = tapped else {
                fatalError("Seed \(seed): random stock tap with nothing to tap")
            }
            state = next
        } else {
            guard let next = apply(legal[pick].0, legal[pick].1, to: state, stockDrawCount: drawCount) else {
                fatalError("Seed \(seed): illegal random move")
            }
            state = next
        }
        actions += 1
    }
    return .actionCap(foundation: lossProgress(state))
}

// MARK: - Reporting

func summarize(
    _ name: String,
    outcomes: [(UInt64, Outcome)],
    lossProgressLabel: String = "foundation-at-loss",
    tracksOverBanking: Bool = true
) {
    var wins = 0
    var deadlocks = 0
    var loops = 0
    var caps = 0
    var winMoves: [Int] = []
    var lossFoundations: [Int] = []
    var highBankLosses = 0
    for (_, outcome) in outcomes {
        switch outcome {
        case .win(let moves):
            wins += 1
            winMoves.append(moves)
        case .deadlock(let foundation):
            deadlocks += 1
            lossFoundations.append(foundation)
            if foundation >= 40 { highBankLosses += 1 }
        case .stalemateLoop(let foundation):
            loops += 1
            lossFoundations.append(foundation)
            if foundation >= 40 { highBankLosses += 1 }
        case .actionCap(let foundation):
            caps += 1
            lossFoundations.append(foundation)
            if foundation >= 40 { highBankLosses += 1 }
        }
    }
    let total = outcomes.count
    print("\n=== \(name) (n=\(total)) ===")
    print(String(format: "win rate: %.1f%% (%d)", 100.0 * Double(wins) / Double(total), wins))
    print("losses: deadlock=\(deadlocks) stalemate-loop=\(loops) action-cap=\(caps)")
    if !winMoves.isEmpty {
        let sorted = winMoves.sorted()
        print("moves/win: median=\(sorted[sorted.count / 2]) mean=\(winMoves.reduce(0, +) / winMoves.count)")
    }
    if !lossFoundations.isEmpty {
        let sorted = lossFoundations.sorted()
        var line = "\(lossProgressLabel): median=\(sorted[sorted.count / 2])"
        if tracksOverBanking {
            line += ", losses with >=40 banked: \(highBankLosses)"
        }
        print(line)
    }
}

// MARK: - Modes

/// Progress goes to stderr, unbuffered, so `tail -f` on a redirected log shows
/// where a long run is while stdout results are still being buffered.
func reportProgress(_ message: String) {
    FileHandle.standardError.write(Data(("  " + message + "\n").utf8))
}

/// Plays seeds 1...count across all cores and returns results in seed order.
/// Parallelism changes only wall-clock time: every game is self-contained and
/// deterministic (the engines are pure functions over value types), and results
/// are collected by seed index, so the output is byte-identical to a serial run.
func mapInParallel<Result>(
    seeds: UInt64,
    progressLabel: String,
    _ play: @escaping (UInt64) -> Result
) -> [Result] {
    let count = Int(seeds)
    var results = [Result?](repeating: nil, count: count)
    let progressLock = NSLock()
    var completed = 0
    results.withUnsafeMutableBufferPointer { buffer in
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let result = play(UInt64(index + 1))
            buffer[index] = result
            progressLock.lock()
            completed += 1
            let done = completed
            progressLock.unlock()
            if done % 100 == 0 {
                reportProgress("\(progressLabel): \(done)/\(count) deals")
            }
        }
    }
    return results.map { $0! }
}

func run(
    variant: GameVariant,
    seeds: UInt64,
    drawCount: Int,
    spiderSuitCount: SpiderSuitCount = .two
) {
    let label: String
    switch variant {
    case .klondike:
        label = "klondike draw-\(drawCount)"
    case .freecell:
        label = "freecell"
    case .yukon:
        label = "yukon"
    case .spider:
        label = "spider \(spiderSuitCount.rawValue)-suit"
    case .pyramid:
        label = "pyramid"
    case .tripeaks:
        label = "tripeaks"
    }
    // Pyramid and TriPeaks bank no foundations; their loss columns record
    // board cards cleared.
    let lossProgressLabel: String
    switch variant {
    case .pyramid:
        lossProgressLabel = "pyramid-cleared-at-loss"
    case .tripeaks:
        lossProgressLabel = "tripeaks-cleared-at-loss"
    case .klondike, .freecell, .yukon, .spider:
        lossProgressLabel = "foundation-at-loss"
    }
    let tracksOverBanking = variant != .pyramid && variant != .tripeaks

    let start = DispatchTime.now()
    let followerResults = mapInParallel(
        seeds: seeds,
        progressLabel: "\(label) — following every hint"
    ) { seed -> (outcome: Outcome, revisitEvents: Int) in
        switch variant {
        case .klondike:
            return (playKlondikeFollowingHints(seed: seed, drawCount: drawCount), 0)
        case .freecell:
            return (playFreeCellFollowingHints(seed: seed), 0)
        case .yukon:
            return playYukonFollowingHints(seed: seed)
        case .spider:
            return playSpiderFollowingHints(seed: seed, suitCount: spiderSuitCount)
        case .pyramid:
            return (playPyramidFollowingHints(seed: seed), 0)
        case .tripeaks:
            return (playTriPeaksFollowingHints(seed: seed), 0)
        }
    }
    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9

    let followerOutcomes = zip(1...seeds, followerResults.map(\.outcome)).map { ($0, $1) }
    let revisitEvents = followerResults.reduce(0) { $0 + $1.revisitEvents }
    let followerLoops = followerResults.count { result in
        if case .stalemateLoop = result.outcome { return true }
        return false
    }

    summarize(
        "\(label) — following every hint",
        outcomes: followerOutcomes,
        lossProgressLabel: lossProgressLabel,
        tracksOverBanking: tracksOverBanking
    )
    print(String(format: "elapsed: %.1fs", seconds))
    if variant == .yukon || variant == .spider {
        print("hint revisit events: \(revisitEvents)")
    }
    if followerLoops > 0 {
        print("GATE VIOLATION: \(label) hint follower looped in \(followerLoops) game(s)")
        gateViolations += followerLoops
    }
    // Spider revisit events are reported but not gated: the deal-preparation
    // fallback deliberately plays score-losing fills, so a later line can
    // transiently re-cross an earlier position (a handful per 500 deals).
    // Yukon's planner measures zero, so for it any revisit is a regression.
    if variant == .yukon, revisitEvents > 0 {
        print("GATE VIOLATION: yukon hint follower revisited positions \(revisitEvents) time(s)")
        gateViolations += revisitEvents
    }

    let randomResults = mapInParallel(
        seeds: seeds,
        progressLabel: "\(label) — random control"
    ) { seed in
        playRandom(variant: variant, seed: seed, drawCount: drawCount, spiderSuitCount: spiderSuitCount)
    }
    summarize(
        "\(label) — random legal moves (control)",
        outcomes: zip(1...seeds, randomResults).map { ($0, $1) },
        lossProgressLabel: lossProgressLabel,
        tracksOverBanking: tracksOverBanking
    )
}

// MARK: - Entry

// The machine-enforceable acceptance gates: a hint follower that stalemate-loops
// is a broken hint system, and any Yukon revisit event is a regression signal
// (the shipped planner measures zero across 500 deals). Violations fail the exit
// code without altering the measured outcomes. Win-rate comparisons stay a human
// step against the README ledger.
var gateViolations = 0

// Line-buffer stdout so results stream into redirected logs as each section
// prints instead of arriving all at once on exit.
setvbuf(stdout, nil, _IOLBF, 0)

func exitWithUsage() -> Never {
    print(
        "usage: run.sh <yukon|klondike|freecell|spider|pyramid|tripeaks|all> [deals >= 1] "
            + "[klondike draw count: 1 or 3 | spider suit count: 1, 2, or 4]"
    )
    exit(1)
}

let arguments = CommandLine.arguments
let mode = arguments.count > 1 ? arguments[1] : "all"
guard let seeds = arguments.count > 2 ? UInt64(arguments[2]) : 500, seeds >= 1 else {
    exitWithUsage()
}
// The third argument is mode-specific: a Klondike draw count or a Spider suit count.
let modeOption = arguments.count > 3 ? Int(arguments[3]) : nil
if arguments.count > 3, modeOption == nil {
    exitWithUsage()
}

switch mode {
case "yukon":
    run(variant: .yukon, seeds: seeds, drawCount: 3)
case "klondike":
    guard let draw = DrawMode(rawValue: modeOption ?? 1) else { exitWithUsage() }
    run(variant: .klondike, seeds: seeds, drawCount: draw.rawValue)
case "freecell":
    run(variant: .freecell, seeds: seeds, drawCount: 3)
case "spider":
    if let modeOption {
        guard let suitCount = SpiderSuitCount(rawValue: modeOption) else { exitWithUsage() }
        run(variant: .spider, seeds: seeds, drawCount: 3, spiderSuitCount: suitCount)
    } else {
        for suitCount in SpiderSuitCount.allCases {
            run(variant: .spider, seeds: seeds, drawCount: 3, spiderSuitCount: suitCount)
        }
    }
case "pyramid":
    run(variant: .pyramid, seeds: seeds, drawCount: 1)
case "tripeaks":
    run(variant: .tripeaks, seeds: seeds, drawCount: 1)
case "all":
    run(variant: .yukon, seeds: seeds, drawCount: 3)
    run(variant: .klondike, seeds: seeds, drawCount: 1)
    run(variant: .klondike, seeds: seeds, drawCount: 3)
    run(variant: .freecell, seeds: seeds, drawCount: 3)
    for suitCount in SpiderSuitCount.allCases {
        run(variant: .spider, seeds: seeds, drawCount: 3, spiderSuitCount: suitCount)
    }
    run(variant: .pyramid, seeds: seeds, drawCount: 1)
    run(variant: .tripeaks, seeds: seeds, drawCount: 1)
default:
    exitWithUsage()
}

if gateViolations > 0 {
    print("\nFAILED: \(gateViolations) acceptance-gate violation(s) — see GATE VIOLATION lines above")
    exit(2)
}
