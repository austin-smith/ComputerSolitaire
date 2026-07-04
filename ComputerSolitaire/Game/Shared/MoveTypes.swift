import Foundation

struct Selection: Equatable {
    enum Source: Equatable {
        case waste
        case freeCell(slot: Int)
        case foundation(pile: Int)
        case tableau(pile: Int, index: Int)
    }

    let source: Source
    let cards: [Card]
}

enum Destination: Equatable {
    case foundation(Int)
    case tableau(Int)
    case freeCell(Int)
}
