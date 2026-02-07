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
    let state: GameState
    let movesCount: Int
    let stockDrawCount: Int
    let history: [GameSnapshot]

    init(
        schemaVersion: Int = SavedGamePayload.currentSchemaVersion,
        state: GameState,
        movesCount: Int,
        stockDrawCount: Int,
        history: [GameSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.movesCount = movesCount
        self.stockDrawCount = stockDrawCount
        self.history = history
    }

    func sanitizedForRestore() -> SavedGamePayload? {
        guard schemaVersion == Self.currentSchemaVersion else { return nil }
        guard state.isValidForPersistence else { return nil }

        let sanitizedStockDrawCount = DrawMode(rawValue: stockDrawCount)?.rawValue ?? DrawMode.three.rawValue
        let sanitizedMovesCount = max(0, movesCount)
        let sanitizedHistory = history
            .filter { $0.movesCount >= 0 && $0.state.isValidForPersistence }
            .suffix(SolitaireViewModel.maxUndoHistoryCount)

        var sanitizedState = state
        sanitizedState.wasteDrawCount = min(
            max(0, sanitizedState.wasteDrawCount),
            min(sanitizedStockDrawCount, sanitizedState.waste.count)
        )

        return SavedGamePayload(
            schemaVersion: schemaVersion,
            state: sanitizedState,
            movesCount: sanitizedMovesCount,
            stockDrawCount: sanitizedStockDrawCount,
            history: Array(sanitizedHistory)
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
