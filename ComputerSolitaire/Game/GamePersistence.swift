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
    let stockDrawCount: Int
    let scoringDrawCount: Int
    let history: [GameSnapshot]
    let redealState: GameState?
    let hasStartedTrackedGame: Bool
    let isCurrentGameFinalized: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case state
        case movesCount
        case score
        case gameStartedAt
        case pauseStartedAt
        case hasAppliedTimeBonus
        case stockDrawCount
        case scoringDrawCount
        case history
        case redealState
        case hasStartedTrackedGame
        case isCurrentGameFinalized
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
        stockDrawCount: Int,
        scoringDrawCount: Int? = nil,
        history: [GameSnapshot],
        redealState: GameState? = nil,
        hasStartedTrackedGame: Bool = true,
        isCurrentGameFinalized: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.state = state
        self.movesCount = movesCount
        self.score = score
        self.gameStartedAt = gameStartedAt
        self.pauseStartedAt = pauseStartedAt
        self.hasAppliedTimeBonus = hasAppliedTimeBonus
        self.stockDrawCount = stockDrawCount
        self.scoringDrawCount = scoringDrawCount ?? stockDrawCount
        self.history = history
        self.redealState = redealState
        self.hasStartedTrackedGame = hasStartedTrackedGame
        self.isCurrentGameFinalized = isCurrentGameFinalized
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
        stockDrawCount = try container.decode(Int.self, forKey: .stockDrawCount)
        scoringDrawCount = try container.decodeIfPresent(Int.self, forKey: .scoringDrawCount) ?? stockDrawCount
        history = try container.decode([GameSnapshot].self, forKey: .history)
        redealState = try container.decodeIfPresent(GameState.self, forKey: .redealState)
        hasStartedTrackedGame = try container.decodeIfPresent(Bool.self, forKey: .hasStartedTrackedGame) ?? true
        isCurrentGameFinalized = try container.decodeIfPresent(Bool.self, forKey: .isCurrentGameFinalized) ?? false
    }

    func sanitizedForRestore() -> SavedGamePayload? {
        guard schemaVersion == Self.currentSchemaVersion else { return nil }
        guard state.isValidForPersistence else { return nil }

        let sanitizedStockDrawCount = DrawMode(rawValue: stockDrawCount)?.rawValue ?? DrawMode.three.rawValue
        let sanitizedMovesCount = max(0, movesCount)
        let sanitizedScore = Scoring.clamped(score)
        let sanitizedSavedAt = min(savedAt, .now)
        let sanitizedStartedAt = min(gameStartedAt, .now)
        let sanitizedScoringDrawCount = DrawMode(rawValue: scoringDrawCount)?.rawValue ?? sanitizedStockDrawCount
        let sanitizedPauseStartedAt = pauseStartedAt
            .map { min($0, .now) }
            .flatMap { $0 >= sanitizedStartedAt ? $0 : nil }
        let sanitizedHasStartedTrackedGame = hasStartedTrackedGame
        let sanitizedIsCurrentGameFinalized = sanitizedHasStartedTrackedGame ? isCurrentGameFinalized : false
        let sanitizedHistory = history
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

        var sanitizedState = state
        sanitizedState.wasteDrawCount = min(
            max(0, sanitizedState.wasteDrawCount),
            min(sanitizedStockDrawCount, sanitizedState.waste.count)
        )

        let sanitizedRedealState: GameState? = {
            guard var baseState = redealState, baseState.isValidForPersistence else { return nil }
            baseState.wasteDrawCount = min(
                max(0, baseState.wasteDrawCount),
                min(sanitizedStockDrawCount, baseState.waste.count)
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
            stockDrawCount: sanitizedStockDrawCount,
            scoringDrawCount: sanitizedScoringDrawCount,
            history: Array(sanitizedHistory),
            redealState: sanitizedRedealState,
            hasStartedTrackedGame: sanitizedHasStartedTrackedGame,
            isCurrentGameFinalized: sanitizedIsCurrentGameFinalized
        )
    }
}

enum GamePersistenceError: Error {
    case invalidPayload
}

enum GamePersistence {
    static func load(from modelContext: ModelContext) -> SavedGamePayload? {
        do {
            guard let record = try fetchCurrentRecord(in: modelContext) else { return nil }
            let payload = try JSONDecoder().decode(SavedGamePayload.self, from: record.snapshotData)
            return payload.sanitizedForRestore()
        } catch {
            return nil
        }
    }

    static func save(_ payload: SavedGamePayload, in modelContext: ModelContext) throws {
        guard let sanitizedPayload = payload.sanitizedForRestore() else {
            throw GamePersistenceError.invalidPayload
        }

        let data = try JSONEncoder().encode(sanitizedPayload)
        if let record = try fetchCurrentRecord(in: modelContext) {
            record.snapshotData = data
            record.updatedAt = .now
        } else {
            modelContext.insert(SavedGameRecord(snapshotData: data))
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

struct GameStatistics: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var gamesPlayed: Int
    var gamesWon: Int
    var totalTimeSeconds: Int
    var bestTimeSeconds: Int?
    var highScoreDrawThree: Int
    var highScoreDrawOne: Int

    init(
        schemaVersion: Int = currentSchemaVersion,
        gamesPlayed: Int = 0,
        gamesWon: Int = 0,
        totalTimeSeconds: Int = 0,
        bestTimeSeconds: Int? = nil,
        highScoreDrawThree: Int = 0,
        highScoreDrawOne: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.gamesPlayed = max(0, gamesPlayed)
        self.gamesWon = max(0, min(gamesWon, gamesPlayed))
        self.totalTimeSeconds = max(0, totalTimeSeconds)
        self.bestTimeSeconds = bestTimeSeconds.map { max(0, $0) }
        self.highScoreDrawThree = max(0, highScoreDrawThree)
        self.highScoreDrawOne = max(0, highScoreDrawOne)
    }

    var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(gamesWon) / Double(gamesPlayed)
    }

    var averageTimeSeconds: Int {
        guard gamesPlayed > 0 else { return 0 }
        return totalTimeSeconds / gamesPlayed
    }

    mutating func recordCompletedGame(
        didWin: Bool,
        elapsedSeconds: Int,
        finalScore: Int,
        drawCount: Int
    ) {
        let sanitizedElapsed = max(0, elapsedSeconds)
        let sanitizedScore = max(0, finalScore)

        gamesPlayed = addingSafely(gamesPlayed, 1)
        totalTimeSeconds = addingSafely(totalTimeSeconds, sanitizedElapsed)

        guard didWin else { return }

        gamesWon = min(gamesPlayed, addingSafely(gamesWon, 1))
        if let bestTimeSeconds {
            self.bestTimeSeconds = min(bestTimeSeconds, sanitizedElapsed)
        } else {
            bestTimeSeconds = sanitizedElapsed
        }

        if drawCount == DrawMode.one.rawValue {
            highScoreDrawOne = max(highScoreDrawOne, sanitizedScore)
        } else {
            highScoreDrawThree = max(highScoreDrawThree, sanitizedScore)
        }
    }

    private func addingSafely(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

enum GameStatisticsStore {
    static let defaultsKey = "stats.gameStatistics"

    static func load(userDefaults: UserDefaults = .standard) -> GameStatistics {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let stats = try? JSONDecoder().decode(GameStatistics.self, from: data),
              stats.schemaVersion == GameStatistics.currentSchemaVersion else {
            return GameStatistics()
        }
        return stats
    }

    static func save(_ stats: GameStatistics, userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }

    static func update(
        userDefaults: UserDefaults = .standard,
        _ mutate: (inout GameStatistics) -> Void
    ) {
        var stats = load(userDefaults: userDefaults)
        mutate(&stats)
        save(stats, userDefaults: userDefaults)
    }
}

private struct CardIdentity: Hashable {
    let suit: Suit
    let rank: Rank
}

private extension GameState {
    var allCards: [Card] {
        stock + waste + foundations.flatMap { $0 } + tableau.flatMap { $0 }
    }

    var isValidForPersistence: Bool {
        guard foundations.count == 4, tableau.count == 7 else { return false }
        guard wasteDrawCount >= 0, wasteDrawCount <= waste.count else { return false }

        let allCards = allCards
        guard allCards.count == 52 else { return false }
        guard Set(allCards.map(\.id)).count == 52 else { return false }
        guard Set(allCards.map { CardIdentity(suit: $0.suit, rank: $0.rank) }).count == 52 else { return false }
        return true
    }
}
