import XCTest
@testable import Computer_Solitaire

@MainActor
final class TriPeaksGeometryTests: XCTestCase {
    func testRowRangesTileTheTwentyEightSlots() {
        XCTAssertEqual(TriPeaksGeometry.rowRanges.count, TriPeaksGeometry.rowCount)
        XCTAssertEqual(TriPeaksGeometry.rowRanges.map(\.count), [3, 6, 9, 10])
        var covered: [Int] = []
        for range in TriPeaksGeometry.rowRanges {
            covered.append(contentsOf: range)
        }
        XCTAssertEqual(covered, Array(0..<TriPeaksGeometry.cardCount))
    }

    func testRowColumnIndexRoundTrip() {
        for index in 0..<TriPeaksGeometry.cardCount {
            let row = TriPeaksGeometry.row(of: index)
            let column = TriPeaksGeometry.column(of: index)
            XCTAssertEqual(TriPeaksGeometry.index(row: row, column: column), index)
        }
    }

    func testCoveringIndices() {
        // Apexes sit over their peak's two row-1 cards.
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 0)?.left, 3)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 0)?.right, 4)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 1)?.left, 5)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 2)?.left, 7)

        // Row 1 covers into its peak's three row-2 cards; the within-peak
        // boundary skips a slot between peaks.
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 3)?.left, 9)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 4)?.left, 10)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 5)?.left, 12)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 6)?.left, 13)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 7)?.left, 15)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 8)?.left, 16)

        // Rows 2 and 3 are contiguous: card j straddles base j and j+1.
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 9)?.left, 18)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 9)?.right, 19)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 17)?.left, 26)
        XCTAssertEqual(TriPeaksGeometry.coveringIndices(of: 17)?.right, 27)

        // The base row is never covered.
        for index in TriPeaksGeometry.rowRanges[3] {
            XCTAssertNil(TriPeaksGeometry.coveringIndices(of: index))
        }
    }

    func testPeakBoundaryGapsInRowTwoCoverage() {
        // Row-2 cards at within-peak boundaries (abs 11 and 12) each cover
        // exactly one row-1 card — the gap between peaks.
        func rowOneSlotsCovered(by rowTwoIndex: Int) -> [Int] {
            TriPeaksGeometry.rowRanges[1].filter { index in
                guard let covering = TriPeaksGeometry.coveringIndices(of: index) else { return false }
                return covering.left == rowTwoIndex || covering.right == rowTwoIndex
            }
        }
        XCTAssertEqual(rowOneSlotsCovered(by: 11), [4])
        XCTAssertEqual(rowOneSlotsCovered(by: 12), [5])
        // Peak-interior row-2 cards cover two row-1 cards.
        XCTAssertEqual(rowOneSlotsCovered(by: 10), [3, 4])
    }

    func testEveryBaseCardCoversSomeRowTwoSlot() {
        for baseIndex in TriPeaksGeometry.rowRanges[3] {
            let coversSomething = TriPeaksGeometry.rowRanges[2].contains { index in
                guard let covering = TriPeaksGeometry.coveringIndices(of: index) else { return false }
                return covering.left == baseIndex || covering.right == baseIndex
            }
            XCTAssertTrue(coversSomething, "Base card \(baseIndex) covers nothing")
        }
    }

    func testUncoveredOnFullAndPartialBoards() {
        let full = GameStateFixtures.seededTriPeaksDeal(seed: 1).triPeaks
        for index in 0..<TriPeaksGeometry.cardCount {
            XCTAssertEqual(
                TriPeaksGeometry.isUncovered(index, in: full),
                TriPeaksGeometry.row(of: index) == TriPeaksGeometry.rowCount - 1,
                "On a full board only the base row is uncovered (slot \(index))"
            )
        }

        // Removing base 18 and 19 uncovers row-2 slot 9; removing just one does not.
        var partial = full
        partial[18] = nil
        XCTAssertFalse(TriPeaksGeometry.isUncovered(9, in: partial))
        partial[19] = nil
        XCTAssertTrue(TriPeaksGeometry.isUncovered(9, in: partial))
    }

    func testSharedBaseCardBlocksBothPeaks() {
        // Base 21 is a coverer for row-2 slots 11 (peak 0) and 12 (peak 1):
        // while it remains, neither uncovers even with its other coverer gone.
        var triPeaks = GameStateFixtures.seededTriPeaksDeal(seed: 1).triPeaks
        triPeaks[20] = nil
        triPeaks[22] = nil
        XCTAssertFalse(TriPeaksGeometry.isUncovered(11, in: triPeaks))
        XCTAssertFalse(TriPeaksGeometry.isUncovered(12, in: triPeaks))
        triPeaks[21] = nil
        XCTAssertTrue(TriPeaksGeometry.isUncovered(11, in: triPeaks))
        XCTAssertTrue(TriPeaksGeometry.isUncovered(12, in: triPeaks))
    }

    func testColumnOffsetUnits() throws {
        // Base card b sits at 2b half-units; every upper card is centered over
        // the two cards covering it.
        for (column, index) in TriPeaksGeometry.rowRanges[3].enumerated() {
            XCTAssertEqual(TriPeaksGeometry.columnOffsetUnits(of: index), Double(2 * column))
        }
        for index in 0..<TriPeaksGeometry.rowRanges[3].lowerBound {
            let covering = try XCTUnwrap(TriPeaksGeometry.coveringIndices(of: index))
            let expected = (TriPeaksGeometry.columnOffsetUnits(of: covering.left)
                + TriPeaksGeometry.columnOffsetUnits(of: covering.right)) / 2
            XCTAssertEqual(TriPeaksGeometry.columnOffsetUnits(of: index), expected)
        }
        XCTAssertEqual(TriPeaksGeometry.columnOffsetUnits(of: 0), 3)
        XCTAssertEqual(TriPeaksGeometry.columnOffsetUnits(of: 1), 9)
        XCTAssertEqual(TriPeaksGeometry.columnOffsetUnits(of: 2), 15)
    }
}
