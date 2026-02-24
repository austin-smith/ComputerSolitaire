import Foundation

struct MoveEvaluation {
    let destination: Destination
    let revealsFaceDownCard: Bool
    let clearsSourcePile: Bool
    let emptyTableauDelta: Int
    let foundationProgressDelta: Int
    let mobilityDelta: Int
    let resultingMobility: Int
    let destinationPriority: Int
}

enum MoveEvaluationRanking {
    // Priority order:
    // 1) reveal hidden cards, 2) increase foundation progress,
    // 3) improve mobility, 4) increase empty tableau columns,
    // 5) clear source pile, 6) destination preference,
    // 7) resulting mobility, 8) deterministic tiebreak.
    static func isBetter(_ lhs: MoveEvaluation, than rhs: MoveEvaluation) -> Bool {
        if lhs.revealsFaceDownCard != rhs.revealsFaceDownCard {
            return lhs.revealsFaceDownCard && !rhs.revealsFaceDownCard
        }
        if lhs.foundationProgressDelta != rhs.foundationProgressDelta {
            return lhs.foundationProgressDelta > rhs.foundationProgressDelta
        }
        if lhs.mobilityDelta != rhs.mobilityDelta {
            return lhs.mobilityDelta > rhs.mobilityDelta
        }
        if lhs.emptyTableauDelta != rhs.emptyTableauDelta {
            return lhs.emptyTableauDelta > rhs.emptyTableauDelta
        }
        if lhs.clearsSourcePile != rhs.clearsSourcePile {
            return lhs.clearsSourcePile && !rhs.clearsSourcePile
        }
        if lhs.destinationPriority != rhs.destinationPriority {
            return lhs.destinationPriority > rhs.destinationPriority
        }
        if lhs.resultingMobility != rhs.resultingMobility {
            return lhs.resultingMobility > rhs.resultingMobility
        }
        return destinationSortKey(lhs.destination) < destinationSortKey(rhs.destination)
    }

    private static func destinationSortKey(_ destination: Destination) -> Int {
        switch destination {
        case .foundation(let index):
            return index
        case .tableau(let index):
            return 100 + index
        case .freeCell(let index):
            return 200 + index
        }
    }
}
