import XCTest
@testable import Computer_Solitaire

@MainActor
final class PyramidGeometryTests: XCTestCase {
    func testRowRangesTileTheTwentyEightSlots() {
        XCTAssertEqual(PyramidGeometry.rowRanges.count, 7)
        for (row, range) in PyramidGeometry.rowRanges.enumerated() {
            XCTAssertEqual(range.count, row + 1, "Row \(row) should hold \(row + 1) slots")
        }
        XCTAssertEqual(PyramidGeometry.rowRanges.first?.lowerBound, 0)
        XCTAssertEqual(PyramidGeometry.rowRanges.last?.upperBound, PyramidGeometry.cardCount)
    }

    func testRowColumnIndexRoundTrip() {
        for index in 0..<PyramidGeometry.cardCount {
            let row = PyramidGeometry.row(of: index)
            let column = PyramidGeometry.column(of: index)
            XCTAssertTrue((0..<7).contains(row))
            XCTAssertTrue((0...row).contains(column))
            XCTAssertEqual(PyramidGeometry.index(row: row, column: column), index)
        }
    }

    func testCoveringIndices() {
        // The apex is covered by the second row; every covered slot's covers are
        // adjacent slots one row below, at the same and next column.
        XCTAssertEqual(PyramidGeometry.coveringIndices(of: 0)?.left, 1)
        XCTAssertEqual(PyramidGeometry.coveringIndices(of: 0)?.right, 2)
        XCTAssertEqual(PyramidGeometry.coveringIndices(of: 3)?.left, 6)
        XCTAssertEqual(PyramidGeometry.coveringIndices(of: 3)?.right, 7)
        XCTAssertEqual(PyramidGeometry.coveringIndices(of: 20)?.left, 26)
        XCTAssertEqual(PyramidGeometry.coveringIndices(of: 20)?.right, 27)
        for index in PyramidGeometry.rowRanges[6] {
            XCTAssertNil(PyramidGeometry.coveringIndices(of: index), "Bottom row is never covered")
        }
    }

    func testExposureOnFullAndPartialPyramids() {
        let full = GameStateFixtures.seededPyramidDeal(seed: 1).pyramid
        for index in 0..<PyramidGeometry.cardCount {
            let isBottomRow = PyramidGeometry.rowRanges[6].contains(index)
            XCTAssertEqual(
                PyramidGeometry.isExposed(index, in: full),
                isBottomRow,
                "On a full pyramid only the bottom row is exposed (slot \(index))"
            )
        }

        // Removing both covers of slot 15 (21 and 22) exposes it; removing only
        // one does not.
        var partial = full
        partial[21] = nil
        XCTAssertFalse(PyramidGeometry.isExposed(15, in: partial))
        partial[22] = nil
        XCTAssertTrue(PyramidGeometry.isExposed(15, in: partial))
    }
}
