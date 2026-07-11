import Foundation
import SwiftData

@Model
final class SavedGameRecord {
    static let currentRecordKey = "current"

    @Attribute(.unique) var key: String
    @Attribute(.externalStorage) var snapshotData: Data
    var updatedAt: Date

    init(
        key: String = SavedGameRecord.currentRecordKey,
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
        usedRedealInCurrentGame: Bool = false
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
    }

    func sanitizedForRestore() -> SavedGamePayload? {
        sanitizedForRestore(at: .now)
    }

    func sanitizedForRestore(at now: Date) -> SavedGamePayload? {
        guard schemaVersion == Self.currentSchemaVersion else { return nil }
        guard state.isValidForPersistence else { return nil }

        let sanitizedStockDrawCount = sanitizedDrawCount(stockDrawCount)
        let sanitizedScoringDrawCount = sanitizedDrawCount(
            scoringDrawCount,
            fallback: sanitizedStockDrawCount
        )
        let sanitizedStartedAt = min(gameStartedAt, now)
        let sanitizedPauseStartedAt = pauseStartedAt
            .map { min($0, now) }
            .flatMap { $0 >= sanitizedStartedAt ? $0 : nil }

        return SavedGamePayload(
            schemaVersion: schemaVersion,
            savedAt: min(savedAt, now),
            state: sanitized(state, stockDrawCount: sanitizedStockDrawCount),
            movesCount: max(0, movesCount),
            score: Scoring.clamped(score),
            gameStartedAt: sanitizedStartedAt,
            pauseStartedAt: sanitizedPauseStartedAt,
            hasAppliedTimeBonus: hasAppliedTimeBonus,
            finalElapsedSeconds: hasAppliedTimeBonus ? finalElapsedSeconds : nil,
            stockDrawCount: sanitizedStockDrawCount,
            scoringDrawCount: sanitizedScoringDrawCount,
            history: sanitizedHistory(),
            redealState: redealState.flatMap {
                $0.isValidForPersistence ? sanitized($0, stockDrawCount: sanitizedStockDrawCount) : nil
            },
            hasStartedTrackedGame: hasStartedTrackedGame,
            isCurrentGameFinalized: hasStartedTrackedGame && isCurrentGameFinalized,
            hintRequestsInCurrentGame: hasStartedTrackedGame ? hintRequestsInCurrentGame : 0,
            undosUsedInCurrentGame: hasStartedTrackedGame ? undosUsedInCurrentGame : 0,
            usedRedealInCurrentGame: hasStartedTrackedGame && usedRedealInCurrentGame
        )
    }

    private func sanitizedDrawCount(_ count: Int, fallback: Int = DrawMode.three.rawValue) -> Int {
        guard state.variant == .klondike else { return DrawMode.three.rawValue }
        return DrawMode(rawValue: count)?.rawValue ?? fallback
    }

    private func sanitized(_ source: GameState, stockDrawCount: Int) -> GameState {
        var result = source
        if result.variant == .klondike {
            result.wasteDrawCount = min(
                max(0, result.wasteDrawCount),
                min(stockDrawCount, result.waste.count)
            )
        } else {
            result.wasteDrawCount = 0
        }
        return result
    }

    private func sanitizedHistory() -> [GameSnapshot] {
        Array(
            history
                .filter { $0.movesCount >= 0 && $0.state.isValidForPersistence }
                .map { snapshot in
                    GameSnapshot(
                        state: snapshot.state,
                        movesCount: snapshot.movesCount,
                        score: Scoring.clamped(snapshot.score),
                        hasAppliedTimeBonus: snapshot.hasAppliedTimeBonus,
                        undoContext: snapshot.undoContext
                    )
                }
                .suffix(SolitaireViewModel.maxUndoHistoryCount)
        )
    }
}

enum GamePersistenceError: Error {
    case invalidPayload
}

enum GamePersistence {
    static func load(from modelContext: ModelContext, now: Date = .now) -> SavedGamePayload? {
        do {
            guard let record = try fetchCurrentRecord(in: modelContext) else { return nil }
            let payload = try JSONDecoder().decode(SavedGamePayload.self, from: record.snapshotData)
            return payload.sanitizedForRestore(at: now)
        } catch {
            return nil
        }
    }

    static func save(_ payload: SavedGamePayload, in modelContext: ModelContext, now: Date = .now) throws {
        guard let sanitizedPayload = payload.sanitizedForRestore(at: now) else {
            throw GamePersistenceError.invalidPayload
        }

        let data = try JSONEncoder().encode(sanitizedPayload)
        if let record = try fetchCurrentRecord(in: modelContext) {
            record.snapshotData = data
            record.updatedAt = now
        } else {
            modelContext.insert(SavedGameRecord(snapshotData: data, updatedAt: now))
        }
        try modelContext.save()
    }

    private static func fetchCurrentRecord(in modelContext: ModelContext) throws -> SavedGameRecord? {
        let key = SavedGameRecord.currentRecordKey
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

struct CompletedGame {
    let didWin: Bool
    let elapsedSeconds: Int
    let finalScore: Int
    let drawCount: Int
    let hintsUsedInGame: Int
    let undosUsedInGame: Int
    let usedRedealInGame: Bool
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
            cleanWins: cleanWins
        )
    }

    mutating func recordCompletedGame(_ game: CompletedGame) {
        let sanitizedElapsed = max(0, game.elapsedSeconds)
        let sanitizedScore = max(0, game.finalScore)
        let sanitizedHintsUsedInGame = max(0, game.hintsUsedInGame)
        let sanitizedUndosUsedInGame = max(0, game.undosUsedInGame)

        gamesPlayed = addingSafely(gamesPlayed, 1)
        totalTimeSeconds = addingSafely(totalTimeSeconds, sanitizedElapsed)

        guard game.didWin else { return }

        gamesWon = min(gamesPlayed, addingSafely(gamesWon, 1))
        if let bestTimeSeconds {
            self.bestTimeSeconds = min(bestTimeSeconds, sanitizedElapsed)
        } else {
            bestTimeSeconds = sanitizedElapsed
        }

        if game.drawCount == DrawMode.one.rawValue {
            highScoreDrawOne = max(highScoreDrawOne ?? 0, sanitizedScore)
        } else if game.drawCount == DrawMode.three.rawValue {
            highScoreDrawThree = max(highScoreDrawThree ?? 0, sanitizedScore)
        }

        let isCleanWin = sanitizedHintsUsedInGame == 0
            && sanitizedUndosUsedInGame == 0
            && !game.usedRedealInGame
        if isCleanWin {
            cleanWins = min(gamesWon, addingSafely(cleanWins, 1))
        }
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
    static func defaultsKey(for variant: GameVariant) -> String {
        "stats.gameStatistics.\(variant.rawValue)"
    }

    static func load(
        for variant: GameVariant,
        userDefaults: UserDefaults = .standard
    ) -> GameStatistics {
        guard let data = userDefaults.data(forKey: defaultsKey(for: variant)),
              let stats = try? JSONDecoder().decode(GameStatistics.self, from: data),
              stats.schemaVersion == GameStatistics.currentSchemaVersion else {
            return GameStatistics()
        }
        return stats
    }

    static func save(
        _ stats: GameStatistics,
        for variant: GameVariant,
        userDefaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        userDefaults.set(data, forKey: defaultsKey(for: variant))
    }

    static func update(
        for variant: GameVariant,
        userDefaults: UserDefaults = .standard,
        _ mutate: (inout GameStatistics) -> Void
    ) {
        var stats = load(for: variant, userDefaults: userDefaults)
        mutate(&stats)
        save(stats, for: variant, userDefaults: userDefaults)
    }

    static func markTrackingStarted(
        for variant: GameVariant,
        userDefaults: UserDefaults = .standard,
        at date: Date = .now
    ) {
        update(for: variant, userDefaults: userDefaults) { stats in
            stats.markTrackingStarted(at: date)
        }
    }

    static func reset(
        for variant: GameVariant,
        userDefaults: UserDefaults = .standard,
        at date: Date = .now
    ) {
        save(GameStatistics(trackedSince: date), for: variant, userDefaults: userDefaults)
    }
}

private struct CardIdentity: Hashable {
    let suit: Suit
    let rank: Rank
}

private extension GameState {
    var allCards: [Card] {
        stock + waste + freeCells.compactMap { $0 } + foundations.flatMap { $0 } + tableau.flatMap { $0 }
    }

    var isValidForPersistence: Bool {
        guard foundations.count == 4 else { return false }
        guard freeCells.count == 4 else { return false }
        guard hasValidVariantPersistenceLayout else { return false }

        let allCards = allCards
        guard allCards.count == 52 else { return false }
        guard Set(allCards.map(\.id)).count == 52 else { return false }
        guard Set(allCards.map { CardIdentity(suit: $0.suit, rank: $0.rank) }).count == 52 else { return false }
        return true
    }

    private var hasValidVariantPersistenceLayout: Bool {
        switch variant {
        case .klondike:
            return KlondikePersistenceRules.hasValidLayout(state: self)
        case .freecell:
            return FreeCellPersistenceRules.hasValidLayout(state: self)
        }
    }
}
