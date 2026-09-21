import XCTest

final class BoardInteractionUITests: XCTestCase {
#if os(iOS)
    @MainActor
    func testDragToFreeCellAndUndoUsesCurrentGeometry() throws {
        try checkFreeCellDragAndUndo(rightToLeft: false)
    }

    @MainActor
    func testRightToLeftFreeCellPreservesPileOrderAndUndo() throws {
        try checkFreeCellDragAndUndo(rightToLeft: true)
    }

    @MainActor
    private func checkFreeCellDragAndUndo(rightToLeft: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotFixture", "freecell"]
        if rightToLeft {
            // Xcode's Right-to-Left Pseudolanguage options work even when the
            // app does not yet ship a translation for a right-to-left language.
            app.launchArguments += ["-AppleTextDirection", "YES",
                                    "-NSForceRightToLeftWritingDirection", "YES"]
        }
        app.launch()

        // This fixture's first tableau ends with the exposed Six of Hearts.
        let card = app.buttons["Six of Hearts"]
        let cell = app.buttons["Free Cell 1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Switch game mode'")).firstMatch
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(title.frame))
        XCTAssertEqual(cell.value as? String, "Empty")
        if rightToLeft {
            XCTAssertGreaterThan(cell.frame.midX, app.buttons["Free Cell 4"].frame.midX,
                                 "Verify actual RTL placement, not just the language request")
        }
        card.press(forDuration: 0.25, thenDragTo: cell)
        waitForValue("Six of Hearts", of: cell)

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        waitForValue("Empty", of: cell)
        XCTAssertTrue(card.exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "freecell-after-drag-and-undo-\(rightToLeft ? "rtl" : "ltr")"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testStockDrawAndUndoRestoresTheWaste() throws {
        try checkStockDrawAndUndo(fixture: "klondike-draw3")
    }

    @MainActor
    func testPyramidStockDrawAndUndo() throws {
        try checkStockDrawAndUndo(fixture: "pyramid")
    }

    @MainActor
    func testTriPeaksStockDrawAndUndo() throws {
        try checkStockDrawAndUndo(fixture: "tripeaks")
    }

    @MainActor
    func testTriPeaksTableauDragAndUndo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotFixture", "tripeaks"]
        app.launch()
        let card = app.buttons["Eight of Diamonds"]
        let waste = app.descendants(matching: .any).matching(identifier: "Waste").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(waste.value as? String, "Seven of Spades")
        XCTAssertEqual(card.frame.width, waste.frame.width, accuracy: 2)
        card.press(forDuration: 0.25, thenDragTo: waste)
        waitForValue("Eight of Diamonds", of: waste)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Undo"].tap()
        waitForValue("Seven of Spades", of: waste)
        XCTAssertTrue(card.exists)
        // Exercise a move from the other half of the continuous board too.
        let otherCard = app.buttons["Six of Diamonds"]
        XCTAssertTrue(otherCard.isHittable)
        otherCard.press(forDuration: 0.25, thenDragTo: waste)
        waitForValue("Six of Diamonds", of: waste)
        app.buttons["Undo"].tap()
        waitForValue("Seven of Spades", of: waste)
        XCTAssertTrue(otherCard.exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "tripeaks-book-after-drag-and-undo"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func checkStockDrawAndUndo(fixture: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotFixture", fixture]
        app.launch()

        let stock = app.buttons["Stock"]
        // Waste is a non-tappable match target in TriPeaks.
        let waste = app.descendants(matching: .any).matching(identifier: "Waste").firstMatch
        XCTAssertTrue(stock.waitForExistence(timeout: 10))
        let initialStock = try XCTUnwrap(stock.value as? String)
        let initialWaste = try XCTUnwrap(waste.value as? String)
        stock.tap()
        let drawn = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialStock), object: stock)
        XCTAssertEqual(XCTWaiter.wait(for: [drawn], timeout: 5), .completed)
        app.buttons["Undo"].tap()
        waitForValue(initialStock, of: stock)
        waitForValue(initialWaste, of: waste)
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement) {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
#endif
}
