import XCTest

/// Runs unchanged on both OS paths: the app selects native dragging at runtime
/// on OS 27 and keeps its gesture implementation on OS 26.
@MainActor
final class CardDraggingUITests: XCTestCase {
    func testDragToFoundationAndUndo() {
        let app = launchFreeCell()
        let ace = card("Ace of Spades", in: app)
        let foundation = app.buttons["Foundation 1"]
        XCTAssertTrue(foundation.waitForExistence(timeout: 5))
        drag(ace, to: foundation)
        assertValue("Ace of Spades", of: foundation)
        activate(app.buttons["Undo"])
        assertValue("Empty", of: foundation)
        XCTAssertTrue(ace.waitForExistence(timeout: 5))
    }

    func testTapToMoveStillWorks() {
        let app = launchFreeCell()
        activate(card("Ace of Spades", in: app))
        assertValue("Ace of Spades", of: app.buttons["Foundation 1"])
        activate(app.buttons["Undo"])
        assertValue("Empty", of: app.buttons["Foundation 1"])
    }

    func testRejectedDropLeavesCardAvailableForAnotherDrag() {
        let app = launchFreeCell()
        let six = card("Six of Hearts", in: app)
        let foundation = app.buttons["Foundation 1"]
        drag(six, to: foundation)
        XCTAssertEqual(foundation.value as? String, "Empty")
        XCTAssertTrue(six.waitForExistence(timeout: 5))

        let freeCell = app.buttons["Free Cell 1"]
        drag(six, to: freeCell)
        assertValue("Six of Hearts", of: freeCell)
    }

    func testStackDragMovesEveryCardAndUndoRestoresSource() {
        let app = launchFreeCell()
        let six = card("Six of Hearts", in: app)
        let five = card("Five of Clubs", in: app)
        drag(five, to: six)
        guard five.wait(for: \.frame.midX, toEqual: six.frame.midX, timeout: 5) else {
            XCTFail("The first drag did not place the five on the six")
            return
        }
        let sourceX = five.frame.midX
        let seven = card("Seven of Clubs", in: app)
        // The six is now partially covered: lift its exposed top edge.
        let start = six.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        drag(start, to: seven.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        XCTAssertTrue(five.waitForExistence(timeout: 5))
        XCTAssertEqual(five.frame.midX, seven.frame.midX, accuracy: 2)
        XCTAssertEqual(six.frame.midX, seven.frame.midX, accuracy: 2)
        activate(app.buttons["Undo"])
        XCTAssertTrue(five.waitForExistence(timeout: 5))
        XCTAssertEqual(five.frame.midX, sourceX, accuracy: 2)
    }

    private func launchFreeCell() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-screenshotFixture", "freecell", "-settings.cardTiltEnabled", "NO"]
#if os(macOS)
        app.launchArguments += ["-screenshotWindowSize", "1100x760", "-ApplePersistenceIgnoreState", "YES"]
#endif
        app.launch()
        XCTAssertTrue(app.buttons["Game: FreeCell. Switch game mode"].waitForExistence(timeout: 10))
        return app
    }

    private func card(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[name]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing card: \(name)")
        return element
    }

    private func assertValue(_ value: String, of element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func activate(_ element: XCUIElement) {
#if os(macOS)
        element.click()
#else
        element.tap()
#endif
    }

    private func drag(_ source: XCUIElement, to destination: XCUIElement) {
        drag(source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
             to: destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
    }

    private func drag(_ source: XCUICoordinate, to destination: XCUICoordinate) {
#if os(macOS)
        source.click(forDuration: 0.2, thenDragTo: destination)
#else
        source.press(forDuration: 1, thenDragTo: destination)
#endif
    }
}
