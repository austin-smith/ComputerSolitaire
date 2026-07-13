import XCTest

/// Exercises the game picker overlay's dismissal affordances end-to-end.
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

        let scrim = app.buttons["Dismiss game picker"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 3), "Picker overlay should open from the title button")

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(scrim.waitForNonExistence(timeout: 3), "Escape should dismiss the picker overlay")
    }

    /// The custom overlay must behave like a system modal for assistive
    /// technologies: obscured board controls leave the accessibility tree.
    @MainActor
    func testPickerHidesBoardAccessibility() throws {
        let app = XCUIApplication()
        app.launch()

        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5), "Game title button should be on the board")
        titleButton.click()

        let scrim = app.buttons["Dismiss game picker"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 3), "Picker overlay should open from the title button")
        XCTAssertTrue(
            titleButton.waitForNonExistence(timeout: 3),
            "The obscured board should leave the accessibility tree while the picker is open"
        )
    }

    /// A window near the supported minimum height can't fit all six family
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
}
