import Foundation

struct GameSnapshot: Codable {
    let state: GameState
    let movesCount: Int
    let score: Int
    let hasAppliedTimeBonus: Bool
    let undoContext: UndoAnimationContext?

    enum CodingKeys: String, CodingKey {
        case state
        case movesCount
        case score
        case hasAppliedTimeBonus
        case undoContext
    }

    init(
        state: GameState,
        movesCount: Int,
        score: Int = 0,
        hasAppliedTimeBonus: Bool = false,
        undoContext: UndoAnimationContext?
    ) {
        self.state = state
        self.movesCount = movesCount
        self.score = score
        self.hasAppliedTimeBonus = hasAppliedTimeBonus
        self.undoContext = undoContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(GameState.self, forKey: .state)
        movesCount = try container.decode(Int.self, forKey: .movesCount)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        hasAppliedTimeBonus = try container.decodeIfPresent(Bool.self, forKey: .hasAppliedTimeBonus) ?? false
        undoContext = try container.decodeIfPresent(UndoAnimationContext.self, forKey: .undoContext)
    }
}

struct UndoAnimationContext: Codable {
    enum Action: String, Codable {
        case moveSelection
        case drawFromStock
        case recycleWaste
        case flipTableauTop
    }

    let action: Action
    let cardIDs: [UUID]
}
