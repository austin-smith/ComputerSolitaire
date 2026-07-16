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
#if os(iOS)
    /// The bottom strip is where a thumb naturally taps to dismiss, and it is
    /// also where the bottom toolbar's chrome used to swallow scrim taps.
    /// Regression coverage: the toolbar must leave while the picker is open,
    /// and a tap in that strip must dismiss the overlay.
    @MainActor
    func testTapOutsideDismissesGamePicker() throws {
        let app = XCUIApplication()
        app.launch()

        let titleButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch game mode'")
        ).firstMatch
        XCTAssertTrue(titleButton.waitForExistence(timeout: 5), "Game title button should be on the board")
        titleButton.tap()

        let scrim = app.buttons["Dismiss game picker"]
        XCTAssertTrue(scrim.waitForExistence(timeout: 3), "Picker overlay should open from the title button")
        XCTAssertTrue(
            app.buttons["Undo"].waitForNonExistence(timeout: 3),
            "The bottom toolbar must leave while the picker is open — its chrome sits above the overlay and would swallow scrim taps"
        )

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()

        XCTAssertTrue(scrim.waitForNonExistence(timeout: 3), "Tapping the bottom strip outside the panel should dismiss the picker overlay")
        XCTAssertTrue(
            app.buttons["Undo"].waitForExistence(timeout: 3),
            "The bottom toolbar should return once the picker closes"
        )
    }
#endif
}
