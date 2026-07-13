import XCTest
@testable import Computer_Solitaire

@MainActor
final class LayoutTests: XCTestCase {
    func testMeasuredHeaderHeightReducesTableauBudget() {
        let boardSize = CGSize(width: 1_200, height: 900)
        let shorterHeader = Layout.metrics(
            for: boardSize,
            tableauColumnCount: 7,
            headerHeight: 66
        )
        let tallerHeader = Layout.metrics(
            for: boardSize,
            tableauColumnCount: 7,
            headerHeight: 82
        )

        XCTAssertLessThan(tallerHeader.cardSize.height, shorterHeader.cardSize.height)
        XCTAssertLessThan(tallerHeader.tableauMaxHeight, shorterHeader.tableauMaxHeight)
    }
}
