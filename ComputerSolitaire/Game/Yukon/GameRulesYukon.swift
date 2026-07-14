/// Yukon's landing rule intentionally matches Klondike's: a group's bottom card
/// lands on an opposite-color card one rank higher, and only Kings fill empty
/// piles. Yukon differs from Klondike in what may be *picked up* (any face-up
/// card with everything above it, regardless of order), not where it may *land* —
/// see `YukonAutoMoveAdvisor.allowsTableauPickup`.
nonisolated enum YukonGameRules {
    static func canMoveToTableau(card: Card, destinationPile: [Card]) -> Bool {
        SharedGameRules.canMoveToKingAnchoredTableau(card: card, destinationPile: destinationPile)
    }
}
