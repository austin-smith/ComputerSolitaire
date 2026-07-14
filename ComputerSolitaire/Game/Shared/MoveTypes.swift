import Foundation

struct Selection: Equatable {
    enum Source: Equatable {
        case waste
        case freeCell(slot: Int)
        case foundation(pile: Int)
        case tableau(pile: Int, index: Int)
        /// A single card at a pyramid slot (Pyramid only).
        case pyramid(index: Int)
        /// A single uncovered card at a TriPeaks slot (TriPeaks only).
        case triPeaks(index: Int)
        /// The face-up top card of the reserve (Canfield only). The reserve is
        /// never a destination.
        case reserve
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
    /// The waste pile. Pyramid removes the selection together with the top
    /// waste card; TriPeaks plays the selection onto the waste, making it the
    /// new match target.
    case waste
    /// Remove a lone King from play (Pyramid only).
    case discard
}
