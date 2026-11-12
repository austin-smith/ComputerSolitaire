import XCTest

final class BoardResizingUITests: XCTestCase {
#if os(iOS)
    /// Run after selecting a fold pose in Device Hub. Do not change orientation:
    /// the simulator's actual display geometry is the subject of this check.
    @MainActor
    func testEveryGameFitsTheCurrentDisplayGeometry() throws {
        for fixture in ScreenshotFixtureCatalog.bundled {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshotFixture", fixture.name]
            app.launch()
            let title = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Switch game mode'")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), fixture.name)
            XCTAssertTrue(title.isHittable, fixture.name)
            let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS ' of '"))
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5), fixture.name)
            let bounds = app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1)
            let hint = app.buttons["Hint"]
            XCTAssertTrue(hint.isHittable, fixture.name)
            let hintFrame = hint.frame
            for card in cards.allElementsBoundByIndex {
                let frame = card.frame
                XCTAssertGreaterThan(frame.width, 0, "\(fixture.name): \(card.label)")
                XCTAssertGreaterThan(frame.height, 0, "\(fixture.name): \(card.label)")
                XCTAssertTrue(bounds.contains(frame), "\(fixture.name): \(card.label) extends offscreen")
                XCTAssertFalse(hintFrame.intersects(frame), "\(fixture.name): \(card.label) overlaps Hint")
            }
            capture(app: app, name: "\(fixture.name)-current-display")
        }
    }

    @MainActor
    func testEveryGamePreservesItsPlayableCardsAcrossRotation() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        for fixture in ScreenshotFixtureCatalog.bundled {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshotFixture", fixture.name]
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            guard waitForOrientation(of: app, landscape: false) else { return }
            let title = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Switch game mode'")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), fixture.name)
            let cardPredicate = NSPredicate(format: "label CONTAINS ' of '")
            let cards = app.buttons.matching(cardPredicate)
            XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5), fixture.name)
            let initialCards = cards.allElementsBoundByIndex.map(\.label).sorted()
            capture(app: app, name: "\(fixture.name)-portrait")

            XCUIDevice.shared.orientation = .landscapeLeft
            guard waitForOrientation(of: app, landscape: true) else { return }
            XCTAssertTrue(title.waitForExistence(timeout: 5), fixture.name)
            XCTAssertEqual(cards.allElementsBoundByIndex.map(\.label).sorted(), initialCards, fixture.name)
            XCTAssertTrue(title.isHittable, fixture.name)
            for card in cards.allElementsBoundByIndex {
                XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(card.frame),
                              "\(fixture.name): \(card.label) extends offscreen")
            }
            capture(app: app, name: "\(fixture.name)-landscape")
        }
    }

    @MainActor
    private func waitForOrientation(of app: XCUIApplication, landscape: Bool) -> Bool {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > 0 && frame.height > 0 && (frame.width > frame.height) == landscape
        }, object: nil)
        let result = XCTWaiter.wait(for: [changed], timeout: 10)
        XCTAssertEqual(result, .completed, "The app did not reach the requested orientation: \(app.windows.firstMatch.frame)")
        return result == .completed
    }

    @MainActor
    private func capture(app: XCUIApplication, name: String) {
        // Scope the capture to the app window on its current display.
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
#endif
}
