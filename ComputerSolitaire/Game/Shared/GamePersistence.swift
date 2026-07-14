import Foundation
import SwiftData

@Model
final class SavedGameRecord {
    /// Single-slot key used before saved games became per-mode.
    static let legacyRecordKey = "current"

    static func key(for mode: GameMode) -> String {
        mode.rawValue
    }

    @Attribute(.unique) var key: String
    @Attribute(.externalStorage) var snapshotData: Data
    var updatedAt: Date

    init(
        key: String,
        snapshotData: Data,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.snapshotData = snapshotData
        self.updatedAt = updatedAt
    }
}

struct SavedGamePayload: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let savedAt: Date
    let state: GameState
    let movesCount: Int
    let score: Int
    let gameStartedAt: Date
    let pauseStartedAt: Date?
    let hasAppliedTimeBonus: Bool
    let finalElapsedSeconds: Int?
    let stockDrawCount: Int
    let scoringDrawCount: Int
    let history: [GameSnapshot]
    let redealState: GameState?
    let hasStartedTrackedGame: Bool
    let isCurrentGameFinalized: Bool
    let hintRequestsInCurrentGame: Int
    let undosUsedInCurrentGame: Int
    let usedRedealInCurrentGame: Bool
    /// The nine-hole Golf match in progress; nil for every other variant.
    /// Lives in the payload — not a side store — so the match restores
    /// atomically with the board it belongs to.
    let golfMatch: GolfMatchState?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case state
        case movesCount
        case score
        case gameStartedAt
        case pauseStartedAt
        case hasAppliedTimeBonus
        case finalElapsedSeconds
        case stockDrawCount
        case scoringDrawCount
        case history
        case redealState
        case hasStartedTrackedGame
        case isCurrentGameFinalized
        case hintRequestsInCurrentGame
        case undosUsedInCurrentGame
        case usedRedealInCurrentGame
        case golfMatch
    }

    init(
        schemaVersion: Int = SavedGamePayload.currentSchemaVersion,
        savedAt: Date = .now,
        state: GameState,
        movesCount: Int,
        score: Int = 0,
        gameStartedAt: Date = .now,
        pauseStartedAt: Date? = nil,
        hasAppliedTimeBonus: Bool = false,
        finalElapsedSeconds: Int? = nil,
        stockDrawCount: Int,
        scoringDrawCount: Int? = nil,
        history: [GameSnapshot],
        redealState: GameState? = nil,
        hasStartedTrackedGame: Bool = true,
        isCurrentGameFinalized: Bool = false,
        hintRequestsInCurrentGame: Int = 0,
        undosUsedInCurrentGame: Int = 0,
        usedRedealInCurrentGame: Bool = false,
        golfMatch: GolfMatchState? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.state = state
        self.movesCount = movesCount
        self.score = score
        self.gameStartedAt = gameStartedAt
        self.pauseStartedAt = pauseStartedAt
        self.hasAppliedTimeBonus = hasAppliedTimeBonus
        self.finalElapsedSeconds = finalElapsedSeconds.map { max(0, $0) }
        self.stockDrawCount = stockDrawCount
        self.scoringDrawCount = scoringDrawCount ?? stockDrawCount
        self.history = history
        self.redealState = redealState
        self.hasStartedTrackedGame = hasStartedTrackedGame
        self.isCurrentGameFinalized = isCurrentGameFinalized
        self.hintRequestsInCurrentGame = max(0, hintRequestsInCurrentGame)
        self.undosUsedInCurrentGame = max(0, undosUsedInCurrentGame)
        self.usedRedealInCurrentGame = usedRedealInCurrentGame
        self.golfMatch = golfMatch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .now
        state = try container.decode(GameState.self, forKey: .state)
        movesCount = try container.decode(Int.self, forKey: .movesCount)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        gameStartedAt = try container.decodeIfPresent(Date.self, forKey: .gameStartedAt) ?? .now
        pauseStartedAt = try container.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        hasAppliedTimeBonus = try container.decodeIfPresent(Bool.self, forKey: .hasAppliedTimeBonus) ?? false
        finalElapsedSeconds = try container.decodeIfPresent(Int.self, forKey: .finalElapsedSeconds).map { max(0, $0) }
        stockDrawCount = try container.decode(Int.self, forKey: .stockDrawCount)
        scoringDrawCount = try container.decodeIfPresent(Int.self, forKey: .scoringDrawCount) ?? stockDrawCount
        history = try container.decode([GameSnapshot].self, forKey: .history)
        redealState = try container.decodeIfPresent(GameState.self, forKey: .redealState)
        hasStartedTrackedGame = try container.decodeIfPresent(Bool.self, forKey: .hasStartedTrackedGame) ?? true
        isCurrentGameFinalized = try container.decodeIfPresent(Bool.self, forKey: .isCurrentGameFinalized) ?? false
        hintRequestsInCurrentGame = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .hintRequestsInCurrentGame) ?? 0
        )
        undosUsedInCurrentGame = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .undosUsedInCurrentGame) ?? 0
        )
        usedRedealInCurrentGame = try container.decodeIfPresent(Bool.self, forKey: .usedRedealInCurrentGame) ?? false
        golfMatch = try container.decodeIfPresent(GolfMatchState.self, forKey: .golfMatch)
    }

    /// The game this payload belongs to. Spider's suit count is derived from
    /// its deal; the draw count is carried alongside the state.
    var gameMode: GameMode {
        GameMode(
            variant: state.variant,
            drawMode: DrawMode(rawValue: stockDrawCount) ?? .three,
            spiderSuitCount: state.spiderSuitCount ?? .two
        )
    }

    /// A copy whose statistics tracking is invalidated: the game stays
    /// playable but can no longer finalize into a statistics bucket.
    /// `hasStartedTrackedGame: false` alone blocks finalization; the other
    /// tracking fields take their canonical untracked values (the same
    /// normal form `sanitizedForRestore` produces).
    func withStatisticsTrackingReset() -> SavedGamePayload {
        SavedGamePayload(
            schemaVersion: schemaVersion,
            savedAt: savedAt,
            state: state,
            movesCount: movesCount,
            score: score,
            gameStartedAt: gameStartedAt,
            pauseStartedAt: pauseStartedAt,
            hasAppliedTimeBonus: hasAppliedTimeBonus,
            finalElapsedSeconds: finalElapsedSeconds,
            stockDrawCount: stockDrawCount,
            scoringDrawCount: scoringDrawCount,
            history: history,
            redealState: redealState,
            hasStartedTrackedGame: false,
            isCurrentGameFinalized: false,
            hintRequestsInCurrentGame: 0,
            undosUsedInCurrentGame: 0,
            usedRedealInCurrentGame: false,
            // The scorecard is gameplay progress and survives the reset; only
            // its statistics eligibility is revoked, so completing the match
            // later cannot finalize pre-reset holes into the fresh bucket.
            golfMatch: golfMatch?.withStatisticsTrackingReset()
        )
    }

    func sanitizedForRestore() -> SavedGamePayload? {
        sanitizedForRestore(at: .now)
    }

    func sanitizedForRestore(at now: Date) -> SavedGamePayload? {
        guard schemaVersion == Self.currentSchemaVersion else { return nil }
        guard state.isValidForPersistence else { return nil }

        let sanitizedStockDrawCount: Int = {
            switch state.variant {
            case .klondike:
                return DrawMode(rawValue: stockDrawCount)?.rawValue ?? DrawMode.three.rawValue
            case .pyramid, .tripeaks, .golf, .fortyThieves:
                // All four always draw a single card to the waste.
                return DrawMode.one.rawValue
            case .freecell, .yukon, .spider, .scorpion:
                return DrawMode.three.rawValue
            case .canfield:
                // Canfield always turns three.
                return DrawMode.three.rawValue
            }
        }()
        let sanitizedMovesCount = max(0, movesCount)
        let sanitizedScore = Scoring.clamped(score, for: state.variant)
        let sanitizedSavedAt = min(savedAt, now)
        let sanitizedStartedAt = min(gameStartedAt, now)
        let sanitizedScoringDrawCount: Int = {
            if state.variant == .klondike {
                return DrawMode(rawValue: scoringDrawCount)?.rawValue ?? sanitizedStockDrawCount
            }
            // Variants without a draw-mode choice score time bonuses on a fixed basis.
            return DrawMode.three.rawValue
        }()
        let sanitizedPauseStartedAt = pauseStartedAt
            .map { min($0, now) }
            .flatMap { $0 >= sanitizedStartedAt ? $0 : nil }
        let sanitizedFinalElapsedSeconds: Int? = {
            guard hasAppliedTimeBonus else { return nil }
            return finalElapsedSeconds.map { max(0, $0) }
        }()
        let sanitizedHasStartedTrackedGame = hasStartedTrackedGame
        let sanitizedIsCurrentGameFinalized = sanitizedHasStartedTrackedGame ? isCurrentGameFinalized : false
        let sanitizedHintRequestsInCurrentGame = sanitizedHasStartedTrackedGame ? max(0, hintRequestsInCurrentGame) : 0
        let sanitizedUndosUsedInCurrentGame = sanitizedHasStartedTrackedGame ? max(0, undosUsedInCurrentGame) : 0
        let sanitizedUsedRedealInCurrentGame = sanitizedHasStartedTrackedGame ? usedRedealInCurrentGame : false
        let sanitizedHistory = history
            .filter { $0.movesCount >= 0 && $0.state.isValidForPersistence }
            .map { snapshot in
                GameSnapshot(
                    state: snapshot.state,
                    movesCount: snapshot.movesCount,
                    score: Scoring.clamped(snapshot.score, for: snapshot.state.variant),
                    hasAppliedTimeBonus: snapshot.hasAppliedTimeBonus,
                    undoContext: snapshot.undoContext
                )
            }
            .suffix(SolitaireViewModel.maxUndoHistoryCount)

        var sanitizedState = state
        sanitizedState.wasteDrawCount = Self.sanitizedWasteDrawCount(
            for: sanitizedState,
            stockDrawCount: sanitizedStockDrawCount
        )

        // The match belongs to Golf alone; a structurally impossible scorecard
        // drops to a fresh match rather than poisoning the restore. Scores are
        // deliberately not clamped to zero — negative hole scores are Golf's
        // best results.
        let sanitizedGolfMatch: GolfMatchState? = {
            guard state.variant == .golf, let golfMatch else { return nil }
            return golfMatch.isValidForPersistence ? golfMatch : nil
        }()

        let sanitizedRedealState: GameState? = {
            guard var baseState = redealState, baseState.isValidForPersistence else { return nil }
            baseState.wasteDrawCount = Self.sanitizedWasteDrawCount(
                for: baseState,
                stockDrawCount: sanitizedStockDrawCount
            )
            return baseState
        }()

        return SavedGamePayload(
            schemaVersion: schemaVersion,
            savedAt: sanitizedSavedAt,
            state: sanitizedState,
            movesCount: sanitizedMovesCount,
            score: sanitizedScore,
            gameStartedAt: sanitizedStartedAt,
            pauseStartedAt: sanitizedPauseStartedAt,
            hasAppliedTimeBonus: hasAppliedTimeBonus,
            finalElapsedSeconds: sanitizedFinalElapsedSeconds,
            stockDrawCount: sanitizedStockDrawCount,
            scoringDrawCount: sanitizedScoringDrawCount,
            history: Array(sanitizedHistory),
            redealState: sanitizedRedealState,
            hasStartedTrackedGame: sanitizedHasStartedTrackedGame,
            isCurrentGameFinalized: sanitizedIsCurrentGameFinalized,
            hintRequestsInCurrentGame: sanitizedHintRequestsInCurrentGame,
            undosUsedInCurrentGame: sanitizedUndosUsedInCurrentGame,
            usedRedealInCurrentGame: sanitizedUsedRedealInCurrentGame,
            golfMatch: sanitizedGolfMatch
        )
    }

    /// Klondike fans up to a draw's worth of waste cards; Pyramid, TriPeaks,
    /// and Golf show a single waste card; the stockless variants keep no
    /// waste at all.
    private static func sanitizedWasteDrawCount(for state: GameState, stockDrawCount: Int) -> Int {
        switch state.variant {
        case .klondike:
            return min(max(0, state.wasteDrawCount), min(stockDrawCount, state.waste.count))
        case .canfield:
            // The exposed waste top is always available, so the fan floors at
            // one card while the waste holds any.
            return min(
                max(min(1, state.waste.count), state.wasteDrawCount),
                min(stockDrawCount, state.waste.count)
            )
        case .pyramid, .tripeaks, .golf, .fortyThieves:
            return min(max(0, state.wasteDrawCount), min(1, state.waste.count))
        case .freecell, .yukon, .spider, .scorpion:
            return 0
        }
    }
}

enum GamePersistenceError: Error {
    case invalidPayload
}

enum GamePersistence {
    static func load(
        mode: GameMode,
        from modelContext: ModelContext,
        now: Date = .now
    ) -> SavedGamePayload? {
        do {
            let key = SavedGameRecord.key(for: mode)
            guard let record = try fetchRecord(forKey: key, in: modelContext) else { return nil }
            let payload = try JSONDecoder().decode(SavedGamePayload.self, from: record.snapshotData)
            guard payload.gameMode == mode else {
                return nil
            }
            return payload.sanitizedForRestore(at: now)
        } catch {
            return nil
        }
    }

    /// Invalidates statistics tracking in the saved sessions of `modes`, so
    /// games that were in progress when their statistics were reset can't
    /// finalize pre-reset play into the fresh buckets. Best effort per slot —
    /// a missing or unreadable slot never blocks the others.
    static func invalidateStatisticsTracking(
        for modes: [GameMode],
        in modelContext: ModelContext,
        now: Date = .now
    ) {
        for mode in modes {
            guard let payload = load(mode: mode, from: modelContext, now: now) else { continue }
            try? save(payload.withStatisticsTrackingReset(), in: modelContext, now: now)
        }
    }

    static func save(_ payload: SavedGamePayload, in modelContext: ModelContext, now: Date = .now) throws {
        guard let sanitizedPayload = payload.sanitizedForRestore(at: now) else {
            throw GamePersistenceError.invalidPayload
        }

        let data = try JSONEncoder().encode(sanitizedPayload)
        let key = SavedGameRecord.key(for: sanitizedPayload.gameMode)
        if let record = try fetchRecord(forKey: key, in: modelContext) {
            record.snapshotData = data
            record.updatedAt = now
        } else {
            modelContext.insert(SavedGameRecord(key: key, snapshotData: data, updatedAt: now))
        }
        try modelContext.save()
    }

    /// Re-keys records from earlier keying schemes (the single "current" slot,
    /// per-variant slots) to their payload's mode slot. Returns the mode of
    /// the game migrated out of the single legacy slot, if any: that game was
    /// on screen when the old build last ran, so first hydration should open
    /// it even when stored settings lag its payload (settings write
    /// immediately; payloads save on a debounced autosave).
    // TODO: Remove (with `SavedGameRecord.legacyRecordKey`) once upgrades
    // from pre-per-mode releases no longer need supporting.
    @discardableResult
    static func migrateLegacyRecordsIfNeeded(in modelContext: ModelContext) -> GameMode? {
        do {
            let modeKeys = Set(GameMode.allCases.map(\.rawValue))
            let records = try modelContext.fetch(FetchDescriptor<SavedGameRecord>())
            var didChange = false
            var migratedCurrentMode: GameMode?

            for record in records where !modeKeys.contains(record.key) {
                didChange = true
                let isLegacyCurrentSlot = record.key == SavedGameRecord.legacyRecordKey
                guard let payload = try? JSONDecoder().decode(
                    SavedGamePayload.self,
                    from: record.snapshotData
                ) else {
                    modelContext.delete(record)
                    continue
                }
                if isLegacyCurrentSlot {
                    migratedCurrentMode = payload.gameMode
                }

                let targetKey = SavedGameRecord.key(
                    for: payload.gameMode
                )
                if let occupyingRecord = try fetchRecord(forKey: targetKey, in: modelContext) {
                    if occupyingRecord.updatedAt >= record.updatedAt {
                        modelContext.delete(record)
                    } else {
                        modelContext.delete(occupyingRecord)
                        record.key = targetKey
                    }
                } else {
                    record.key = targetKey
                }
            }

            if didChange {
                try modelContext.save()
            }
            return migratedCurrentMode
        } catch {
            // Leave the store untouched; hydration falls back to a fresh deal.
            return nil
        }
    }

    private static func fetchRecord(forKey key: String, in modelContext: ModelContext) throws -> SavedGameRecord? {
        var descriptor = FetchDescriptor<SavedGameRecord>(
            predicate: #Predicate<SavedGameRecord> { record in
                record.key == key
            },
            sortBy: [SortDescriptor(\SavedGameRecord.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

struct GameStatistics: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var trackedSince: Date?
    var gamesPlayed: Int
    var gamesWon: Int
    var totalTimeSeconds: Int
    var bestTimeSeconds: Int?
    var highScoreDrawThree: Int?
    var highScoreDrawOne: Int?
    /// High score for variants without a game-mode split (FreeCell, Yukon,
    /// Pyramid). Klondike wins record into the per-draw-mode fields above and
    /// Spider wins into the per-suit-count fields below instead.
    var highScore: Int?
    var highScoreOneSuit: Int?
    var highScoreTwoSuits: Int?
    var highScoreFourSuits: Int?
    /// Best (lowest) Golf hole score. Unclamped: Golf strokes run lower-is-
    /// better and clearing the board can leave a negative score, so negatives
    /// are legal results here, never corruption.
    var lowestScore: Int?
    var golfMatchesCompleted: Int
    /// Best (lowest) nine-hole Golf match total; unclamped like `lowestScore`.
    var bestMatchTotal: Int?
    var cleanWins: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case trackedSince
        case gamesPlayed
        case gamesWon
        case totalTimeSeconds
        case bestTimeSeconds
        case highScoreDrawThree
        case highScoreDrawOne
        case highScore
        case highScoreOneSuit
        case highScoreTwoSuits
        case highScoreFourSuits
        case lowestScore
        case golfMatchesCompleted
        case bestMatchTotal
        case cleanWins
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        trackedSince: Date? = nil,
        gamesPlayed: Int = 0,
        gamesWon: Int = 0,
        totalTimeSeconds: Int = 0,
        bestTimeSeconds: Int? = nil,
        highScoreDrawThree: Int? = nil,
        highScoreDrawOne: Int? = nil,
        highScore: Int? = nil,
        highScoreOneSuit: Int? = nil,
        highScoreTwoSuits: Int? = nil,
        highScoreFourSuits: Int? = nil,
        lowestScore: Int? = nil,
        golfMatchesCompleted: Int = 0,
        bestMatchTotal: Int? = nil,
        cleanWins: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.trackedSince = trackedSince
        self.gamesPlayed = max(0, gamesPlayed)
        self.gamesWon = max(0, min(gamesWon, gamesPlayed))
        self.totalTimeSeconds = max(0, totalTimeSeconds)
        self.bestTimeSeconds = bestTimeSeconds.map { max(0, $0) }
        self.highScoreDrawThree = highScoreDrawThree.map { max(0, $0) }
        self.highScoreDrawOne = highScoreDrawOne.map { max(0, $0) }
        self.highScore = highScore.map { max(0, $0) }
        self.highScoreOneSuit = highScoreOneSuit.map { max(0, $0) }
        self.highScoreTwoSuits = highScoreTwoSuits.map { max(0, $0) }
        self.highScoreFourSuits = highScoreFourSuits.map { max(0, $0) }
        self.lowestScore = lowestScore
        self.golfMatchesCompleted = max(0, golfMatchesCompleted)
        self.bestMatchTotal = bestMatchTotal
        self.cleanWins = max(0, min(cleanWins, self.gamesWon))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? Self.currentSchemaVersion
        let decodedGamesPlayed = max(0, try container.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0)
        let decodedGamesWon = max(
            0,
            min(
                try container.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0,
                decodedGamesPlayed
            )
        )

        schemaVersion = decodedSchemaVersion
        trackedSince = try container.decodeIfPresent(Date.self, forKey: .trackedSince)
        gamesPlayed = decodedGamesPlayed
        gamesWon = decodedGamesWon
        totalTimeSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .totalTimeSeconds) ?? 0)
        bestTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .bestTimeSeconds).map { max(0, $0) }
        highScoreDrawThree = try container.decodeIfPresent(Int.self, forKey: .highScoreDrawThree).map { max(0, $0) }
        highScoreDrawOne = try container.decodeIfPresent(Int.self, forKey: .highScoreDrawOne).map { max(0, $0) }
        highScore = try container.decodeIfPresent(Int.self, forKey: .highScore).map { max(0, $0) }
        highScoreOneSuit = try container.decodeIfPresent(Int.self, forKey: .highScoreOneSuit).map { max(0, $0) }
        highScoreTwoSuits = try container.decodeIfPresent(Int.self, forKey: .highScoreTwoSuits).map { max(0, $0) }
        highScoreFourSuits = try container.decodeIfPresent(Int.self, forKey: .highScoreFourSuits).map { max(0, $0) }
        lowestScore = try container.decodeIfPresent(Int.self, forKey: .lowestScore)
        golfMatchesCompleted = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .golfMatchesCompleted) ?? 0
        )
        bestMatchTotal = try container.decodeIfPresent(Int.self, forKey: .bestMatchTotal)
        cleanWins = max(
            0,
            min(
                try container.decodeIfPresent(Int.self, forKey: .cleanWins) ?? 0,
                decodedGamesWon
            )
        )
    }

    var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(gamesWon) / Double(gamesPlayed)
    }

    var averageTimeSeconds: Int {
        guard gamesPlayed > 0 else { return 0 }
        return totalTimeSeconds / gamesPlayed
    }

    var cleanWinRate: Double {
        guard gamesWon > 0 else { return 0 }
        return Double(cleanWins) / Double(gamesWon)
    }

    static func aggregated(_ statsByVariant: [GameStatistics]) -> GameStatistics {
        var gamesPlayed = 0
        var gamesWon = 0
        var totalTimeSeconds = 0
        var cleanWins = 0
        var trackedSince: Date?
        var bestTimeSeconds: Int?
        var highScoreDrawThree: Int?
        var highScoreDrawOne: Int?
        var highScore: Int?
        var highScoreOneSuit: Int?
        var highScoreTwoSuits: Int?
        var highScoreFourSuits: Int?
        var lowestScore: Int?
        var golfMatchesCompleted = 0
        var bestMatchTotal: Int?

        for stats in statsByVariant {
            gamesPlayed = addingSafely(gamesPlayed, stats.gamesPlayed)
            gamesWon = addingSafely(gamesWon, stats.gamesWon)
            totalTimeSeconds = addingSafely(totalTimeSeconds, stats.totalTimeSeconds)
            cleanWins = addingSafely(cleanWins, stats.cleanWins)

            if let candidate = stats.trackedSince {
                if let existing = trackedSince {
                    trackedSince = min(existing, candidate)
                } else {
                    trackedSince = candidate
                }
            }

            if let candidate = stats.bestTimeSeconds {
                if let existing = bestTimeSeconds {
                    bestTimeSeconds = min(existing, candidate)
                } else {
                    bestTimeSeconds = candidate
                }
            }

            if let candidate = stats.highScoreDrawThree {
                highScoreDrawThree = max(highScoreDrawThree ?? 0, candidate)
            }
            if let candidate = stats.highScoreDrawOne {
                highScoreDrawOne = max(highScoreDrawOne ?? 0, candidate)
            }
            if let candidate = stats.highScore {
                highScore = max(highScore ?? 0, candidate)
            }
            if let candidate = stats.highScoreOneSuit {
                highScoreOneSuit = max(highScoreOneSuit ?? 0, candidate)
            }
            if let candidate = stats.highScoreTwoSuits {
                highScoreTwoSuits = max(highScoreTwoSuits ?? 0, candidate)
            }
            if let candidate = stats.highScoreFourSuits {
                highScoreFourSuits = max(highScoreFourSuits ?? 0, candidate)
            }
            if let candidate = stats.lowestScore {
                lowestScore = min(lowestScore ?? candidate, candidate)
            }
            golfMatchesCompleted = addingSafely(golfMatchesCompleted, stats.golfMatchesCompleted)
            if let candidate = stats.bestMatchTotal {
                bestMatchTotal = min(bestMatchTotal ?? candidate, candidate)
            }
        }

        gamesWon = min(gamesWon, gamesPlayed)
        cleanWins = min(cleanWins, gamesWon)

        return GameStatistics(
            trackedSince: trackedSince,
            gamesPlayed: gamesPlayed,
            gamesWon: gamesWon,
            totalTimeSeconds: totalTimeSeconds,
            bestTimeSeconds: bestTimeSeconds,
            highScoreDrawThree: highScoreDrawThree,
            highScoreDrawOne: highScoreDrawOne,
            highScore: highScore,
            highScoreOneSuit: highScoreOneSuit,
            highScoreTwoSuits: highScoreTwoSuits,
            highScoreFourSuits: highScoreFourSuits,
            lowestScore: lowestScore,
            golfMatchesCompleted: golfMatchesCompleted,
            bestMatchTotal: bestMatchTotal,
            cleanWins: cleanWins
        )
    }

    mutating func recordCompletedGame(
        didWin: Bool,
        elapsedSeconds: Int,
        finalScore: Int,
        drawCount: Int,
        spiderSuitCount: SpiderSuitCount? = nil,
        lowerScoreIsBetter: Bool = false,
        hintsUsedInGame: Int,
        undosUsedInGame: Int,
        usedRedealInGame: Bool
    ) {
        let sanitizedElapsed = max(0, elapsedSeconds)
        let sanitizedScore = max(0, finalScore)
        let sanitizedHintsUsedInGame = max(0, hintsUsedInGame)
        let sanitizedUndosUsedInGame = max(0, undosUsedInGame)

        gamesPlayed = addingSafely(gamesPlayed, 1)
        totalTimeSeconds = addingSafely(totalTimeSeconds, sanitizedElapsed)

        guard didWin else { return }

        gamesWon = min(gamesPlayed, addingSafely(gamesWon, 1))
        if let bestTimeSeconds {
            self.bestTimeSeconds = min(bestTimeSeconds, sanitizedElapsed)
        } else {
            bestTimeSeconds = sanitizedElapsed
        }

        // Golf's stroke scores are lower-is-better and record per completed
        // hole through `recordCompletedGolfHole` (a win's negative final would
        // sanitize to zero here); the high-score fields never apply to it.
        if !lowerScoreIsBetter {
            if let spiderSuitCount {
                // Spider difficulties aren't score-comparable, so each suit count
                // keeps its own high score (mirroring Klondike's draw-mode split).
                switch spiderSuitCount {
                case .one:
                    highScoreOneSuit = max(highScoreOneSuit ?? 0, sanitizedScore)
                case .two:
                    highScoreTwoSuits = max(highScoreTwoSuits ?? 0, sanitizedScore)
                case .four:
                    highScoreFourSuits = max(highScoreFourSuits ?? 0, sanitizedScore)
                }
            } else if drawCount == DrawMode.one.rawValue {
                highScoreDrawOne = max(highScoreDrawOne ?? 0, sanitizedScore)
            } else if drawCount == DrawMode.three.rawValue {
                highScoreDrawThree = max(highScoreDrawThree ?? 0, sanitizedScore)
            } else {
                // Variants without a draw mode (FreeCell, Yukon, Pyramid) keep a
                // single high score.
                highScore = max(highScore ?? 0, sanitizedScore)
            }
        }

        let isCleanWin = sanitizedHintsUsedInGame == 0
            && sanitizedUndosUsedInGame == 0
            && !usedRedealInGame
        if isCleanWin {
            cleanWins = min(gamesWon, addingSafely(cleanWins, 1))
        }
    }

    /// Records a finished Golf hole's stroke score, won or dead — every hole
    /// played to its end has one, and best means lowest. Unsanitized on
    /// purpose: negative scores (a cleared board banking leftover stock) are
    /// Golf's best results, never corruption. Abandoned holes must not reach
    /// this — their live score is a snapshot of an unfinished hole.
    mutating func recordCompletedGolfHole(score: Int) {
        lowestScore = min(lowestScore ?? score, score)
    }

    /// Records a finished nine-hole Golf match; best means lowest, and
    /// negative totals are legal results, never corruption.
    mutating func recordCompletedGolfMatch(total: Int) {
        golfMatchesCompleted = addingSafely(golfMatchesCompleted, 1)
        bestMatchTotal = min(bestMatchTotal ?? total, total)
    }

    mutating func markTrackingStarted(at date: Date = .now) {
        if trackedSince == nil {
            trackedSince = date
        }
    }

    mutating func reset(at date: Date = .now) {
        self = GameStatistics(trackedSince: date)
    }

    private func addingSafely(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    private static func addingSafely(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

enum GameStatisticsStore {
    /// Key of the pooled Klondike bucket used before statistics became per-mode.
    static let legacyKlondikeDefaultsKey = "stats.gameStatistics.klondike"

    /// Key of the pooled Spider bucket used before statistics became per-mode.
    static let legacySpiderDefaultsKey = "stats.gameStatistics.spider"

    static func defaultsKey(for mode: GameMode) -> String {
        "stats.gameStatistics.\(mode.rawValue)"
    }

    static func load(
        for mode: GameMode,
        userDefaults: UserDefaults = .standard
    ) -> GameStatistics {
        guard let data = userDefaults.data(forKey: defaultsKey(for: mode)),
              let stats = try? JSONDecoder().decode(GameStatistics.self, from: data),
              stats.schemaVersion == GameStatistics.currentSchemaVersion else {
            return GameStatistics()
        }
        return stats
    }

    static func save(
        _ stats: GameStatistics,
        for mode: GameMode,
        userDefaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        userDefaults.set(data, forKey: defaultsKey(for: mode))
    }

    static func update(
        for mode: GameMode,
        userDefaults: UserDefaults = .standard,
        _ mutate: (inout GameStatistics) -> Void
    ) {
        var stats = load(for: mode, userDefaults: userDefaults)
        mutate(&stats)
        save(stats, for: mode, userDefaults: userDefaults)
    }

    static func markTrackingStarted(
        for mode: GameMode,
        userDefaults: UserDefaults = .standard,
        at date: Date = .now
    ) {
        update(for: mode, userDefaults: userDefaults) { stats in
            stats.markTrackingStarted(at: date)
        }
    }

    static func reset(
        for mode: GameMode,
        userDefaults: UserDefaults = .standard,
        at date: Date = .now
    ) {
        save(GameStatistics(trackedSince: date), for: mode, userDefaults: userDefaults)
    }

    /// Splits the pooled pre-per-mode Klondike bucket. Games, wins, and time
    /// were pooled across draw modes and are assigned to the mode in active
    /// use; high scores were always recorded per mode and go to their own
    /// buckets.
    // TODO: Remove (with `legacyKlondikeDefaultsKey`) once upgrades from
    // pre-per-mode releases no longer need supporting.
    static func migrateLegacyKlondikeStatisticsIfNeeded(
        activeDrawMode: DrawMode,
        userDefaults: UserDefaults = .standard
    ) {
        guard let data = userDefaults.data(forKey: legacyKlondikeDefaultsKey) else { return }
        userDefaults.removeObject(forKey: legacyKlondikeDefaultsKey)
        guard let legacy = try? JSONDecoder().decode(GameStatistics.self, from: data),
              legacy.schemaVersion == GameStatistics.currentSchemaVersion else {
            return
        }

        let activeMode = GameMode(variant: .klondike, drawMode: activeDrawMode)
        let otherMode: GameMode = activeMode == .klondikeDrawOne ? .klondikeDrawThree : .klondikeDrawOne

        var activeStats = legacy
        var otherStats = GameStatistics(trackedSince: legacy.trackedSince)
        if activeMode == .klondikeDrawOne {
            activeStats.highScoreDrawThree = nil
            otherStats.highScoreDrawThree = legacy.highScoreDrawThree
        } else {
            activeStats.highScoreDrawOne = nil
            otherStats.highScoreDrawOne = legacy.highScoreDrawOne
        }

        save(activeStats, for: activeMode, userDefaults: userDefaults)
        save(otherStats, for: otherMode, userDefaults: userDefaults)
    }

    /// Splits the pooled pre-per-mode Spider bucket, mirroring the Klondike
    /// migration. Games, wins, and time were pooled across suit counts and
    /// are assigned to the mode in active use; high scores were always
    /// recorded per suit count and go to their own buckets.
    // TODO: Remove (with `legacySpiderDefaultsKey`) once upgrades from
    // pre-per-mode releases no longer need supporting.
    static func migrateLegacySpiderStatisticsIfNeeded(
        activeSuitCount: SpiderSuitCount,
        userDefaults: UserDefaults = .standard
    ) {
        guard let data = userDefaults.data(forKey: legacySpiderDefaultsKey) else { return }
        userDefaults.removeObject(forKey: legacySpiderDefaultsKey)
        guard let legacy = try? JSONDecoder().decode(GameStatistics.self, from: data),
              legacy.schemaVersion == GameStatistics.currentSchemaVersion else {
            return
        }

        let activeMode = GameMode(variant: .spider, spiderSuitCount: activeSuitCount)
        for mode in GameMode.modes(for: .spider) {
            var stats = mode == activeMode
                ? legacy
                : GameStatistics(trackedSince: legacy.trackedSince)
            stats.highScoreOneSuit = mode == .spiderOneSuit ? legacy.highScoreOneSuit : nil
            stats.highScoreTwoSuits = mode == .spiderTwoSuits ? legacy.highScoreTwoSuits : nil
            stats.highScoreFourSuits = mode == .spiderFourSuits ? legacy.highScoreFourSuits : nil
            save(stats, for: mode, userDefaults: userDefaults)
        }
    }
}

private extension GameState {
    var allCards: [Card] {
        stock + waste + freeCells.compactMap { $0 } + foundations.flatMap { $0 }
            + tableau.flatMap { $0 } + pyramid.compactMap { $0 } + discard
            + triPeaks.compactMap { $0 } + reserve
    }

    var isValidForPersistence: Bool {
        guard foundations.count == variant.foundationPileCount else { return false }
        guard freeCells.count == 4 else { return false }
        guard hasValidVariantPersistenceLayout else { return false }

        let allCards = allCards
        guard allCards.count == variant.deckCardCount else { return false }
        guard Set(allCards.map(\.id)).count == variant.deckCardCount else { return false }
        guard hasExpectedDeckComposition(allCards) else { return false }
        return true
    }

    /// Every card identity must appear exactly as often as the variant's deck
    /// composition prescribes: once each for the single-deck variants, twice
    /// each for Forty Thieves' two full decks, and per `SpiderDeck` for
    /// Spider's two suit-composed decks.
    private func hasExpectedDeckComposition(_ allCards: [Card]) -> Bool {
        var identityCounts: [CardIdentity: Int] = [:]
        for card in allCards {
            identityCounts[CardIdentity(suit: card.suit, rank: card.rank), default: 0] += 1
        }
        return identityCounts == expectedIdentityCounts
    }

    private var expectedIdentityCounts: [CardIdentity: Int] {
        switch variant {
        case .klondike, .freecell, .yukon, .pyramid, .tripeaks, .golf, .scorpion, .canfield:
            return Self.uniformIdentityCounts(copies: 1)
        case .fortyThieves:
            return Self.uniformIdentityCounts(copies: 2)
        case .spider:
            guard let suitCount = spiderSuitCount else { return [:] }
            return SpiderDeck.expectedIdentityCounts(suitCount: suitCount)
        }
    }

    private static func uniformIdentityCounts(copies: Int) -> [CardIdentity: Int] {
        var counts: [CardIdentity: Int] = [:]
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                counts[CardIdentity(suit: suit, rank: rank)] = copies
            }
        }
        return counts
    }

    private var hasValidVariantPersistenceLayout: Bool {
        switch variant {
        case .klondike:
            return KlondikePersistenceRules.hasValidLayout(state: self)
        case .freecell:
            return FreeCellPersistenceRules.hasValidLayout(state: self)
        case .yukon:
            return YukonPersistenceRules.hasValidLayout(state: self)
        case .spider:
            return SpiderPersistenceRules.hasValidLayout(state: self)
        case .pyramid:
            return PyramidPersistenceRules.hasValidLayout(state: self)
        case .tripeaks:
            return TriPeaksPersistenceRules.hasValidLayout(state: self)
        case .golf:
            return GolfPersistenceRules.hasValidLayout(state: self)
        case .fortyThieves:
            return FortyThievesPersistenceRules.hasValidLayout(state: self)
        case .scorpion:
            return ScorpionPersistenceRules.hasValidLayout(state: self)
        case .canfield:
            return CanfieldPersistenceRules.hasValidLayout(state: self)
        }
    }
}
