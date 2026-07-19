import CoreGraphics
import Foundation

/// Builds the forward flight for a stock-onto-tableau deal (Spider's ten-card
/// row, Scorpion's three-card stock): overlay cards leave the stock in pile
/// order, flip face up in the air, and land on their piles' tops. The mirror
/// of `UndoAnimationCoordinator`'s `.dealTableauRow` flight, which flies the
/// same cards back to the same stock anchors.
enum DealAnimationCoordinator {
    struct Plan {
        let cards: [DrawAnimationCard]
        let cardIDs: Set<UUID>
        let token: UUID
        let travelDuration: Double
        /// Spring tail after the nominal travel time; the overlay comes down
        /// once the cards have visibly settled.
        let settleDuration: Double
        /// The last card's takeoff delay; the whole deal is done after
        /// `maxDelay + travelDuration + settleDuration`.
        let maxDelay: Double
    }

    /// Per-card takeoff stagger: the packet leaves the stock as one quick
    /// left-to-right sweep, reading as a deal rather than simultaneous pops.
    static let staggerInterval: Double = 0.05

    /// One pace for every deal flight — the stock deal and the fresh-board
    /// deal must never drift apart.
    static let travelDuration: Double = 0.32
    static let settleDuration: Double = 0.12

    /// `dealtCards` in pile order (leftmost pile's card first). Cards without
    /// a published frame — a card banked the instant it landed — are skipped;
    /// they surface through the banking animation instead.
    static func makeDealPlan(
        dealtCards: [Card],
        cardFrames: [UUID: CGRect],
        stockFrame: CGRect
    ) -> Plan? {
        guard !dealtCards.isEmpty, stockFrame != .zero else { return nil }

        var items: [DrawAnimationCard] = []
        for (index, card) in dealtCards.enumerated() {
            guard let startFrame = UndoAnimationCoordinator.stockAnchorFrame(
                for: index,
                stockFrame: stockFrame
            ),
                let endFrame = cardFrames[card.id] else {
                continue
            }
            items.append(
                DrawAnimationCard(
                    id: card.id,
                    card: card,
                    start: CGPoint(x: startFrame.midX, y: startFrame.midY),
                    end: CGPoint(x: endFrame.midX, y: endFrame.midY),
                    delay: staggerInterval * Double(index)
                )
            )
        }
        guard !items.isEmpty else { return nil }

        return Plan(
            cards: items,
            cardIDs: Set(items.map(\.id)),
            token: UUID(),
            travelDuration: travelDuration,
            settleDuration: settleDuration,
            maxDelay: items.last?.delay ?? 0
        )
    }

    /// The whole fresh deal's takeoff window: per-card stagger shrinks as the
    /// deal grows, so Klondike's 28 cards and Spider's 54 read as one sweep
    /// of the same length rather than a parade that scales with card count.
    static let newGameTakeoffWindow: Double = 1.0

    /// A fresh board's cards in the order a dealer lays them down: the
    /// reserve packet is set down first (only its exposed top card flies —
    /// the buried cards render as the set-down stack), the tableau deals in
    /// left-to-right passes, the pyramid and peaks build from the top row
    /// down, and starter cards (Canfield's foundation base, Golf's and
    /// TriPeaks' waste card) turn over last. Zones a variant doesn't deal to
    /// are empty, so the one ordering serves every variant.
    static func newGameDealSequence(in state: GameState) -> [Card] {
        var sequence: [Card] = []
        if let reserveTop = state.reserve.last {
            sequence.append(reserveTop)
        }
        let tallestPileCount = state.tableau.map(\.count).max() ?? 0
        for row in 0..<tallestPileCount {
            for pile in state.tableau where row < pile.count {
                sequence.append(pile[row])
            }
        }
        sequence.append(contentsOf: state.pyramid.compactMap { $0 })
        sequence.append(contentsOf: state.triPeaks.compactMap { $0 })
        sequence.append(contentsOf: state.foundations.flatMap { $0 })
        sequence.append(contentsOf: state.waste)
        return sequence
    }

    /// Builds the deal-in flight for a fresh board (new game, redeal, Golf's
    /// next hole): every dealt card flies from the stock to its slot,
    /// face-down cards traveling face-down and face-up cards flipping in the
    /// air like the draw flight's. Stockless variants (FreeCell, Yukon) deal
    /// from an invisible deck just above the board's top edge instead.
    static func makeNewGameDealPlan(
        dealtCards: [Card],
        cardFrames: [UUID: CGRect],
        stockFrame: CGRect,
        boardSize: CGSize
    ) -> Plan? {
        let flying = dealtCards.compactMap { card -> (card: Card, frame: CGRect)? in
            guard let frame = cardFrames[card.id] else { return nil }
            return (card, frame)
        }
        guard !flying.isEmpty else { return nil }

        let start: CGPoint
        if stockFrame != .zero {
            start = CGPoint(x: stockFrame.midX, y: stockFrame.midY)
        } else {
            guard boardSize != .zero else { return nil }
            let cardHeight = flying[0].frame.height
            start = CGPoint(x: boardSize.width * 0.5, y: -cardHeight)
        }

        let stagger = min(
            staggerInterval,
            newGameTakeoffWindow / Double(max(1, flying.count - 1))
        )
        let items = flying.enumerated().map { index, item -> DrawAnimationCard in
            DrawAnimationCard(
                id: item.card.id,
                card: item.card,
                start: start,
                end: CGPoint(x: item.frame.midX, y: item.frame.midY),
                delay: stagger * Double(index)
            )
        }

        return Plan(
            cards: items,
            cardIDs: Set(items.map(\.id)),
            token: UUID(),
            travelDuration: travelDuration,
            settleDuration: settleDuration,
            maxDelay: items.last?.delay ?? 0
        )
    }
}
