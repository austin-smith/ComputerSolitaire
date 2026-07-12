import Foundation

/// Resolves where a tapped selection should move.
///
/// Unlike hint planning, a tap always resolves to the best *legal* destination so a tap
/// never dead-ends while a legal move exists. Destination preference is deterministic:
/// higher tier wins, then a larger resulting build, then the lowest pile index.
enum TapMovePolicy {
    static func bestDestination(for selection: Selection, in state: GameState) -> Destination? {
        // Tapping a foundation card only selects it; pulling cards back off the
        // foundation is deliberate enough to require a drag.
        if case .foundation = selection.source { return nil }

        let destinations = AutoMoveAdvisor.legalDestinations(for: selection, in: state)
        guard !destinations.isEmpty else { return nil }

        var best: (destination: Destination, priority: Priority)?
        for destination in destinations {
            let priority = priority(of: destination, for: selection, in: state)
            if best.map({ priority.isBetter(than: $0.priority) }) ?? true {
                best = (destination, priority)
            }
        }
        return best?.destination
    }

    /// The single best legal move across every pickable selection, using the same
    /// destination preferences as taps. Used as the hint of last resort when the
    /// FreeCell solver can't find a winning line.
    static func bestMove(in state: GameState) -> (selection: Selection, destination: Destination)? {
        var best: (selection: Selection, destination: Destination, priority: Priority)?
        for selection in AutoMoveAdvisor.candidateSelections(in: state) {
            if case .foundation = selection.source { continue }
            for destination in AutoMoveAdvisor.legalDestinations(for: selection, in: state) {
                let priority = priority(of: destination, for: selection, in: state)
                if best.map({ priority.isBetter(than: $0.priority) }) ?? true {
                    best = (selection, destination, priority)
                }
            }
        }
        return best.map { ($0.selection, $0.destination) }
    }

    /// A card is safe to send to the foundation when doing so can never cost the game:
    /// aces and twos always are; a higher card is safe once both opposite-color foundations
    /// reach at least rank − 1 and the other same-color foundation reaches rank − 2.
    static func isSafeFoundationMove(card: Card, in state: GameState) -> Bool {
        let rank = card.rank.rawValue
        if rank <= 2 { return true }

        var topRankBySuit: [Suit: Int] = [:]
        for foundation in state.foundations {
            if let top = foundation.last {
                topRankBySuit[top.suit] = top.rank.rawValue
            }
        }

        let oppositeMin = Suit.allCases
            .filter { $0.isRed != card.suit.isRed }
            .map { topRankBySuit[$0] ?? 0 }
            .min() ?? 0
        let sameColorOther = Suit.allCases
            .first { $0.isRed == card.suit.isRed && $0 != card.suit }
        let sameColorOtherRank = sameColorOther.flatMap { topRankBySuit[$0] } ?? 0

        return oppositeMin >= rank - 1 && sameColorOtherRank >= rank - 2
    }
}

private extension TapMovePolicy {
    struct Priority {
        let tier: Int
        let buildLength: Int
        let pileOrder: Int

        func isBetter(than other: Priority) -> Bool {
            if tier != other.tier { return tier > other.tier }
            if buildLength != other.buildLength { return buildLength > other.buildLength }
            return pileOrder > other.pileOrder
        }
    }

    static func priority(
        of destination: Destination,
        for selection: Selection,
        in state: GameState
    ) -> Priority {
        switch destination {
        case .foundation(let index):
            guard let card = selection.cards.first else {
                return Priority(tier: 0, buildLength: 0, pileOrder: -index)
            }
            let tier: Int
            switch state.variant {
            case .klondike:
                tier = 100
            case .freecell, .yukon:
                // No stock to refill the board: an eager unsafe foundation move can
                // strand a card another pile still needs as a landing spot.
                tier = isSafeFoundationMove(card: card, in: state) ? 100 : 60
            }
            return Priority(tier: tier, buildLength: 0, pileOrder: -index)

        case .tableau(let index):
            let pile = state.tableau[index]
            let tier = pile.isEmpty ? 40 : 80
            return Priority(
                tier: tier,
                buildLength: topRunLength(of: pile) + selection.cards.count,
                pileOrder: -index
            )

        case .freeCell(let index):
            return Priority(tier: 20, buildLength: 0, pileOrder: -index)
        }
    }

    /// Length of the valid descending, alternating-color run ending at the pile's top card.
    static func topRunLength(of pile: [Card]) -> Int {
        guard var index = pile.indices.last else { return 0 }
        var length = 1
        while index > 0 {
            let upper = pile[index - 1]
            let lower = pile[index]
            guard upper.isFaceUp,
                  upper.suit.isRed != lower.suit.isRed,
                  lower.rank.rawValue == upper.rank.rawValue - 1 else {
                break
            }
            length += 1
            index -= 1
        }
        return length
    }
}
