import Foundation

/// A nine-hole Golf match: the stroke scores of the holes finished so far.
/// Each hole's score is a self-contained `Int` finalized exactly once, when
/// the player advances past it (`SolitaireViewModel.advanceGolfHole`), so the
/// match total is a plain sum. Lower is better throughout, and negative
/// scores are legal results (a cleared board banks one bonus stroke per
/// leftover stock card).
struct GolfMatchState: Codable, Equatable {
    static let holeCount = 9
    /// Traditional par framing: a nine-hole total of 45 or under is par.
    static let parTotal = 45

    /// Stroke scores of finished holes, in play order (fewer than nine
    /// mid-match).
    var completedHoleScores: [Int] = []
    /// Whether completing this match may record into statistics. Cleared when
    /// statistics are reset mid-match — the pre-reset holes in the total must
    /// not finalize into the fresh bucket, mirroring how per-game tracking is
    /// invalidated — while the scorecard itself plays on untouched (resets
    /// erase statistics, never gameplay progress).
    var countsTowardStatistics = true

    enum CodingKeys: String, CodingKey {
        case completedHoleScores
        case countsTowardStatistics
    }

    init(completedHoleScores: [Int] = [], countsTowardStatistics: Bool = true) {
        self.completedHoleScores = completedHoleScores
        self.countsTowardStatistics = countsTowardStatistics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedHoleScores = try container.decodeIfPresent([Int].self, forKey: .completedHoleScores) ?? []
        countsTowardStatistics = try container.decodeIfPresent(
            Bool.self,
            forKey: .countsTowardStatistics
        ) ?? true
    }

    /// The hole currently being played, 1-based; stays at nine once the
    /// match is complete (the summary presents over the final board).
    var currentHoleNumber: Int {
        min(completedHoleScores.count + 1, Self.holeCount)
    }

    var runningTotal: Int {
        completedHoleScores.reduce(0, +)
    }

    var isComplete: Bool {
        completedHoleScores.count == Self.holeCount
    }

    /// The same match with statistics eligibility revoked; the payload-level
    /// counterpart of `SavedGamePayload.withStatisticsTrackingReset`.
    func withStatisticsTrackingReset() -> GolfMatchState {
        GolfMatchState(completedHoleScores: completedHoleScores, countsTowardStatistics: false)
    }

    /// Structural bounds for restoring a persisted match: at most nine holes,
    /// each within the range a real hole can produce (+35 for an untouched
    /// board down to −16 for a board cleared without a single draw).
    var isValidForPersistence: Bool {
        guard completedHoleScores.count <= Self.holeCount else { return false }
        return completedHoleScores.allSatisfy { score in
            (-GolfGameRules.dealStockCardCount...GolfGameRules.dealTableauCardCount)
                .contains(score)
        }
    }
}
