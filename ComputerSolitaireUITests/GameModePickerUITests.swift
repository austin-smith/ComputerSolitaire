import XCTest

/// Exercises native game-picker presentation and navigation.
final class GameModePickerUITests: XCTestCase {
#if os(macOS)
    @MainActor
    func testEscapeDismissesGamePicker() throws {
        let app = XCUIApplication()
        app.launch()

        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5), "Game title button should be on the board")
        titleButton.click()

        let closeButton = app.buttons["Dismiss game picker"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "Picker sheet should open from the title button")

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3), "Escape should dismiss the picker sheet")
    }

    /// Rely on the system's sheet semantics for modal accessibility.
    @MainActor
    func testPickerUsesNativeSheet() throws {
        let app = XCUIApplication()
        app.launch()

        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5), "Game title button should be on the board")
        titleButton.click()

        let closeButton = app.buttons["Dismiss game picker"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "Picker sheet should open from the title button")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists, "The picker should expose native sheet semantics")
        XCTAssertTrue(sheet.buttons["Dismiss game picker"].isHittable)
        closeButton.click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
        XCTAssertTrue(titleButton.isHittable)
    }

    /// A window near the supported minimum height can't fit all the family
    /// cards; the picker must fall back to scrolling so every game stays
    /// reachable.
    @MainActor
    func testShortWindowKeepsEveryGameReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-screenshotWindowSize", "900x420"]
        app.launch()

        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5), "Game title button should be on the board")
        titleButton.click()

        let yukonCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Yukon'")
        ).firstMatch
        XCTAssertTrue(yukonCard.waitForExistence(timeout: 3), "Picker should list every game")

        if !yukonCard.isHittable {
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        }
        XCTAssertTrue(yukonCard.isHittable, "The last game card must be reachable in a short window")
        yukonCard.click()

        let yukonTitle = app.buttons["Game: Yukon. Switch game mode"]
        XCTAssertTrue(yukonTitle.waitForExistence(timeout: 3), "Selecting the scrolled-to game should switch to it")
    }
#endif
#if os(iOS)
    @MainActor
    func testNativePickerAccessibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotFixture", "freecell"]
        app.launch()
        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Switch game mode'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        XCTAssertTrue(app.buttons["Dismiss game picker"].waitForExistence(timeout: 3))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testOverflowKeepsGameActionsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotFixture", "klondike-draw3"]
        app.launch()
        let more = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'more'")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), app.debugDescription)
        more.tap()
        for action in ["New Game", "Restart", "Statistics", "Rules & Scoring", "Settings"] {
            XCTAssertTrue(app.buttons[action].waitForExistence(timeout: 3), action)
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCloseDismissesGamePickerAndRestoresBoard() throws {
        let app = XCUIApplication()
        app.launch()
        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5))
        titleButton.tap()
        let closeButton = app.buttons["Dismiss game picker"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))
        XCTAssertTrue(titleButton.isHittable)
    }

    @MainActor
    func testPickerNavigationSurvivesRotation() throws {
        let app = XCUIApplication()
        app.launch()
        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5))
        titleButton.tap()
        let klondike = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Klondike'")).firstMatch
        XCTAssertTrue(klondike.waitForExistence(timeout: 3))
        klondike.tap()
        let initialSize = app.windows.firstMatch.frame.size
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.size != initialSize && frame.width > frame.height && frame.height > 0
        }, object: nil)
        let rotationResult = XCTWaiter.wait(for: [rotated], timeout: 10)
        XCTAssertEqual(rotationResult, .completed, "The device did not actually rotate")
        guard rotationResult == .completed else { return }
        let threeCard = app.buttons.matching(NSPredicate(format: "label CONTAINS '3-card'")).firstMatch
        XCTAssertTrue(threeCard.waitForExistence(timeout: 3))
        threeCard.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Switch game mode'"))
            .firstMatch.waitForExistence(timeout: 3))
    }

#endif
}
