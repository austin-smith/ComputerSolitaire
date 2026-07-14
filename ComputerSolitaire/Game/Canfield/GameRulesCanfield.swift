import Foundation

nonisolated enum CanfieldGameRules {
    static let tableauPileCount = 4
    static let reserveCardCount = 13
    /// The 52-card deal minus the reserve, the base card, and four tableau cards.
    static let dealStockCardCount = 34
    static let stockDrawCount = 3

    /// The rank all four foundations start with: the base card the deal turned
    /// onto the first foundation. Foundations are locked, so a seeded pile
    /// never empties and the base rank can always be read back off the board.
    static func baseRank(in state: GameState) -> Rank? {
        state.foundations.compactMap(\.first).first?.rank
    }

    /// How many steps above the base rank `rank` sits, turning the corner:
    /// the base rank is offset zero and the rank just below it is offset
    /// twelve, the last card a foundation takes.
    static func foundationOffset(of rank: Rank, from base: Rank) -> Int {
        (rank.rawValue - base.rawValue + Rank.allCases.count) % Rank.allCases.count
    }

    /// Foundation landing rule: an empty pile takes only the base rank;
    /// otherwise the moving card goes on the top card of the same suit, one
    /// rank higher, turning the corner from King to Ace.
    static func canMoveToFoundation(card: Card, foundation: [Card], in state: GameState) -> Bool {
        guard let top = foundation.last else {
            return card.rank == baseRank(in: state)
        }
        return top.suit == card.suit && card.rank.rawValue == wrappedRankAbove(top.rank)
    }

    /// Tableau landing rule: the moving card goes on a face-up top card of
    /// the opposite color, one rank higher, turning the corner from Ace up to
    /// King. An empty pile is open on card alone — whether a source may
    /// actually take a space is `allowsTableauTransfer`'s source-aware call.
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        guard let top = destinationPile.last else { return true }
        return top.isFaceUp
            && top.suit.isRed != card.suit.isRed
            && top.rank.rawValue == wrappedRankAbove(card.rank)
    }

    /// Source-aware transfer gate shared by drags and the advisor. Foundations
    /// are locked, so a foundation card never returns to the tableau. Between
    /// tableau piles Canfield moves a pile only in its entirety — a selection
    /// lifted above the pile bottom is a partial sequence and never transfers.
    /// A space refills from the reserve automatically; once the reserve is
    /// out, only the top waste card may take a space, at the player's choice.
    static func allowsTableauTransfer(
        selection: Selection,
        destinationPile: [Card],
        in state: GameState
    ) -> Bool {
        if case .foundation = selection.source { return false }
        if case .tableau(_, let index) = selection.source, index != 0 { return false }
        guard destinationPile.isEmpty else { return true }
        guard state.reserve.isEmpty else { return false }
        if case .waste = selection.source { return true }
        return false
    }

    /// A packed run: face-up cards descending one rank per step in
    /// alternating colors, turning the corner from Ace down to King. Deals
    /// and legal landings only ever build packed piles, so every whole pile
    /// satisfies this; it guards hand-built and restored states.
    static func isPackedSequence(_ cards: [Card]) -> Bool {
        guard !cards.isEmpty else { return false }
        guard cards.allSatisfy(\.isFaceUp) else { return false }
        for index in 0..<(cards.count - 1) {
            let upper = cards[index]
            let lower = cards[index + 1]
            guard upper.suit.isRed != lower.suit.isRed else { return false }
            guard upper.rank.rawValue == wrappedRankAbove(lower.rank) else { return false }
        }
        return true
    }

    /// The fan count after the top waste card is played (call with the card
    /// already removed): one fewer fanned card, but never zero while the
    /// waste holds any — the exposed top card is always available in
    /// Canfield, so a spent fan uncovers the card beneath it rather than
    /// burying the pile until the next stock action.
    static func wasteDrawCountAfterWastePlay(in state: GameState) -> Int {
        max(min(1, state.waste.count), state.wasteDrawCount - 1)
    }

    /// The compulsory space fill: as soon as a tableau pile empties, the
    /// reserve's exposed card moves in and the next reserve card turns face
    /// up. Player choice only enters once the reserve is exhausted.
    static func refillEmptyPileFromReserve(on state: inout GameState, pileIndex: Int) {
        guard state.tableau.indices.contains(pileIndex),
              state.tableau[pileIndex].isEmpty,
              !state.reserve.isEmpty else { return }
        var card = state.reserve.removeLast()
        card.isFaceUp = true
        state.tableau[pileIndex].append(card)
        if let newTopIndex = state.reserve.indices.last {
            state.reserve[newTopIndex].isFaceUp = true
        }
    }

    /// Whether sending `card` to a foundation can never cost the game.
    /// Foundations are locked, so an eager send is irrevocable. The classic
    /// two-step rule applies in offset space: a base-plus-one card is safe
    /// because the only cards that land on it are base cards, themselves
    /// foundation-playable at once; a higher card is safe once both
    /// opposite-color foundations reach at least its offset minus one and the
    /// other same-color foundation its offset minus two. Base cards are
    /// treated as safe outright: each foundation can only ever begin with its
    /// suit's base card, so withholding one defers mandatory progress.
    /// (Strictly, a promoted base card stops hosting wrapped offset-twelve
    /// landings, but ranking a foundation start below any tableau build is
    /// the far worse trade.)
    static func isSafeFoundationMove(card: Card, in state: GameState) -> Bool {
        guard let base = baseRank(in: state) else { return false }
        let offset = foundationOffset(of: card.rank, from: base)
        if offset <= 1 { return true }

        var topOffsetBySuit: [Suit: Int] = [:]
        for foundation in state.foundations {
            if let first = foundation.first {
                topOffsetBySuit[first.suit] = foundation.count - 1
            }
        }

        let oppositeMin = Suit.allCases
            .filter { $0.isRed != card.suit.isRed }
            .map { topOffsetBySuit[$0] ?? -1 }
            .min() ?? -1
        let sameColorOther = Suit.allCases
            .first { $0.isRed == card.suit.isRed && $0 != card.suit }
        let sameColorOtherOffset = sameColorOther.flatMap { topOffsetBySuit[$0] } ?? -1

        return oppositeMin >= offset - 1 && sameColorOtherOffset >= offset - 2
    }
}

nonisolated private extension CanfieldGameRules {
    /// The raw rank one step above `rank`, turning the corner from King to Ace.
    static func wrappedRankAbove(_ rank: Rank) -> Int {
        rank.rawValue % Rank.allCases.count + 1
    }
}
