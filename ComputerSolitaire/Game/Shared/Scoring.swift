import Foundation

enum ScoringAction {
    case wasteToTableau
    case wasteToFoundation
    case tableauToFoundation
    case turnOverTableauCard
    case foundationToTableau
    case recycleWasteInDrawOne
}

enum Scoring {
    static let minimumScore = 0
    static let timedPointsLostPerSecond = 1
    static let timedMaxBonusDrawOne = 600
    static let timedMaxBonusDrawThree = 900

    static func delta(for action: ScoringAction) -> Int {
        switch action {
        case .wasteToTableau:
            return 5
        case .wasteToFoundation:
            return 10
        case .tableauToFoundation:
            return 10
        case .turnOverTableauCard:
            return 5
        case .foundationToTableau:
            return -15
        case .recycleWasteInDrawOne:
            return -100
        }
    }

    static func applying(_ action: ScoringAction, to score: Int) -> Int {
        clamped(score + delta(for: action))
    }

    static func clamped(_ score: Int) -> Int {
        max(minimumScore, score)
    }

    static func timeBonus(
        elapsedSeconds: Int,
        maxBonus: Int,
        pointsLostPerSecond: Int = timedPointsLostPerSecond
    ) -> Int {
        guard elapsedSeconds > 0, maxBonus > 0, pointsLostPerSecond > 0 else {
            return max(0, maxBonus)
        }
        return max(0, maxBonus - (elapsedSeconds * pointsLostPerSecond))
    }

    static func timedMaxBonus(for drawCount: Int) -> Int {
        if drawCount == DrawMode.one.rawValue {
            return timedMaxBonusDrawOne
        }
        return timedMaxBonusDrawThree
    }
}
