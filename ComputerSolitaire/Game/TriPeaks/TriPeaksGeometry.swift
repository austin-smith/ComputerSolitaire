import Foundation

/// Index math for the 4-row, 28-card TriPeaks layout: three overlapping peaks
/// over a shared base row.
///
/// Slots are row-major — row 0 holds the three apexes (one per peak), row 1
/// holds 6 cards (two per peak), row 2 holds 9 cards (three per peak), and
/// row 3 is the contiguous 10-card base. The peaks overlap at the base: rows
/// 2 and 3 are contiguous runs, so the base cards under adjacent peak
/// boundaries are shared between two peaks. Every slot above the base row is
/// covered by two slots in the row below; the upper rows have horizontal gaps
/// between peaks, which is why covering indices are computed per row rather
/// than by a single triangular formula.
nonisolated enum TriPeaksGeometry {
    static let rowCount = 4
    static let cardCount = 28
    static let peakCount = 3
    static let baseRowLength = 10

    /// Apexes, then rows of 6 and 9, then the 10-card base.
    static let rowRanges: [Range<Int>] = [0..<3, 3..<9, 9..<18, 18..<28]

    /// The apex slot of each peak; clearing all three clears the board (each
    /// apex is only removable once its whole subtree below is gone, and the
    /// three subtrees cover every slot).
    static let apexIndices = [0, 1, 2]

    static func row(of index: Int) -> Int {
        rowRanges.firstIndex { $0.contains(index) } ?? 0
    }

    static func column(of index: Int) -> Int {
        index - rowRanges[row(of: index)].lowerBound
    }

    static func index(row: Int, column: Int) -> Int {
        rowRanges[row].lowerBound + column
    }

    /// The two slots covering `index` in the row below; nil for the base row.
    static func coveringIndices(of index: Int) -> (left: Int, right: Int)? {
        let row = Self.row(of: index)
        let column = Self.column(of: index)
        switch row {
        case 0:
            // Apex p sits over its peak's two row-1 cards.
            let left = Self.index(row: 1, column: 2 * column)
            return (left: left, right: left + 1)
        case 1:
            // Row-1 card m of peak g sits over row-2 cards 3g+m and 3g+m+1;
            // the row-2 cards at peak boundaries cover only one row-1 card.
            let peak = column / 2
            let left = Self.index(row: 2, column: 3 * peak + column % 2)
            return (left: left, right: left + 1)
        case 2:
            // Rows 2 and 3 are contiguous: card j straddles base j and j+1.
            let left = Self.index(row: 3, column: column)
            return (left: left, right: left + 1)
        default:
            return nil
        }
    }

    /// A slot is uncovered when neither covering slot holds a card.
    static func isUncovered(_ index: Int, in triPeaks: [Card?]) -> Bool {
        guard let covering = coveringIndices(of: index) else { return true }
        return triPeaks[covering.left] == nil && triPeaks[covering.right] == nil
    }

    /// Horizontal slot position in half-card layout units, where one unit is
    /// half of (card width + column spacing). Base card b sits at 2b; each
    /// upper card is centered over the two cards it is covered by.
    static func columnOffsetUnits(of index: Int) -> Double {
        let column = column(of: index)
        switch row(of: index) {
        case 0:
            return Double(6 * column + 3)
        case 1:
            return Double(6 * (column / 2) + 2 * (column % 2) + 2)
        case 2:
            return Double(2 * column + 1)
        default:
            return Double(2 * column)
        }
    }
}
