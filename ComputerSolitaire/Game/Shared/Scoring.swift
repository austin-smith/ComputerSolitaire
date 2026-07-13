import Foundation

enum ScoringAction {
    case wasteToTableau
    case wasteToFoundation
    case tableauToFoundation
    case turnOverTableauCard
    case foundationToTableau
    case recycleWasteInDrawOne
    case spiderMove
    case spiderCompletedRun
    case removePyramidPair
    case removePyramidKing
    /// The n-th consecutive TriPeaks discard in a chain scores n points.
    case triPeaksChainDiscard(chainLength: Int)
    case triPeaksPeakClear
    /// Clearing the third peak always clears the whole board, so this bonus
    /// replaces (not joins) the third `triPeaksPeakClear`.
    case triPeaksBoardClear
    case triPeaksStockFlip
    /// Golf strokes count down: each card played off the board is one fewer
    /// stroke against you.
    case golfBoardPlay
    /// Clearing the Golf board banks one bonus stroke per card left in the
    /// stock, making the final score negative — traditional golf's best
    /// outcome.
    case golfBoardClear(remainingStockCount: Int)
}

enum Scoring {
    static let minimumScore = 0
    static let timedPointsLostPerSecond = 1
    static let timedMaxBonusDrawOne = 600
    static let timedMaxBonusDrawThree = 900
    /// Classic Spider scoring starts every game at 500.
    static let spiderInitialScore = 500

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
        case .spiderMove:
            return -1
        case .spiderCompletedRun:
            return 100
        case .removePyramidPair:
            return 10
        case .removePyramidKing:
            return 5
        case .triPeaksChainDiscard(let chainLength):
            return max(0, chainLength)
        case .triPeaksPeakClear:
            return 15
        case .triPeaksBoardClear:
            return 30
        case .triPeaksStockFlip:
            return -5
        case .golfBoardPlay:
            return -1
        case .golfBoardClear(let remainingStockCount):
            return -max(0, remainingStockCount)
        }
    }

    static func applying(_ action: ScoringAction, to score: Int, variant: GameVariant) -> Int {
        clamped(score + delta(for: action), for: variant)
    }

    /// Golf's stroke score is exempt from the floor: clearing the board
    /// subtracts a point per leftover stock card, so negative finals are the
    /// best results. Every other variant floors at `minimumScore`.
    static func clamped(_ score: Int, for variant: GameVariant) -> Int {
        variant.lowerScoreIsBetter ? score : max(minimumScore, score)
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
