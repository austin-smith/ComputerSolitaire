import Foundation

struct Selection: Equatable {
    enum Source: Equatable {
        case waste
        case freeCell(slot: Int)
        case foundation(pile: Int)
        case tableau(pile: Int, index: Int)
        /// A single card at a pyramid slot (Pyramid only).
        case pyramid(index: Int)
    }

    let source: Source
    let cards: [Card]
}

enum Destination: Equatable {
    case foundation(Int)
    case tableau(Int)
    case freeCell(Int)
    /// Remove the selection together with the card at this pyramid slot (Pyramid only).
    case pyramid(Int)
    /// Remove the selection together with the top waste card (Pyramid only).
    case waste
    /// Remove a lone King from play (Pyramid only).
    case discard
}
