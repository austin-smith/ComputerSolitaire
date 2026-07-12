import Foundation

/// Index math for the 7-row, 28-card pyramid.
///
/// Slots are row-major: row `r` (0-based, apex first) occupies indices
/// `r(r+1)/2 ..< (r+1)(r+2)/2`, so row 0 is slot 0 and row 6 is slots 21...27.
/// Each slot except the bottom row is covered by two slots in the row below.
enum PyramidGeometry {
    static let rowCount = 7
    static let cardCount = 28

    static let rowRanges: [Range<Int>] = (0..<rowCount).map { row in
        (row * (row + 1) / 2)..<((row + 1) * (row + 2) / 2)
    }

    static func row(of index: Int) -> Int {
        rowRanges.firstIndex { $0.contains(index) } ?? 0
    }

    static func column(of index: Int) -> Int {
        index - rowRanges[row(of: index)].lowerBound
    }

    static func index(row: Int, column: Int) -> Int {
        rowRanges[row].lowerBound + column
    }

    /// The two slots covering `index` in the row below; nil for the bottom row.
    static func coveringIndices(of index: Int) -> (left: Int, right: Int)? {
        let row = Self.row(of: index)
        guard row < rowCount - 1 else { return nil }
        let left = Self.index(row: row + 1, column: Self.column(of: index))
        return (left: left, right: left + 1)
    }

    /// A slot is exposed when neither covering slot holds a card.
    static func isExposed(_ index: Int, in pyramid: [Card?]) -> Bool {
        guard let covering = coveringIndices(of: index) else { return true }
        return pyramid[covering.left] == nil && pyramid[covering.right] == nil
    }
}
