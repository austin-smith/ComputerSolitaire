import XCTest
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Captures App Store screenshots: launches the app once per staged board
/// (see `ScreenshotFixtures` in the app target) and captures the screen.
/// Run `fastlane screenshots` to drive this across every device size; images
/// land in `fastlane/screenshots/`. On iOS runs fastlane's `snapshot()` does
/// the capture; the macOS leg (which snapshot doesn't support) runs this same
/// test via xcodebuild and collects the attachment instead.
final class ScreenshotCaptureUITests: XCTestCase {
    /// Kept in sync with `ScreenshotFixtures.bundled` by hand: UI tests run in
    /// a separate process and cannot import the app module. One board per App
    /// Store screenshot, in store order.
    private static let boards = [
        "klondike-draw3",
        "freecell",
        "yukon",
        "spider"
    ]

    /// Appearance for every screenshot, pinned via UserDefaults launch
    /// arguments so simulator state can't change the look between runs.
    private static let appearance = [
        "-settings.tableBackgroundColor", "#67a3d9", // sky
        "-settings.cardStyle", "classic",
        "-settings.feltEffectEnabled", "YES"
    ]

#if os(macOS)
    /// Full window size in points — title bar and toolbar included, since
    /// the toolbar holds the app's controls and belongs in the screenshot.
    /// On a 2x display the capture comes out at 2880x1800 pixels — an exact
    /// Mac App Store screenshot size.
    private static let windowSize = CGSize(width: 1440, height: 900)
#endif

    @MainActor
    func testCaptureScreenshots() throws {
#if os(macOS)
        // The app pins its *content* size (pure SwiftUI; the app target has
        // no AppKit), but the capture needs the *window* to be exactly
        // `windowSize`. Probe once to measure the title-bar height, then pin
        // the content that much shorter for the real captures.
        let titleBarHeight = try measureTitleBarHeight()
        let contentSize = CGSize(
            width: Self.windowSize.width,
            height: Self.windowSize.height - titleBarHeight
        )
#endif
        for board in Self.boards {
            let app = XCUIApplication()
#if os(macOS)
            // Ignore any persisted window state so the app-side pin always wins.
            app.launchArguments += [
                "-screenshotWindowSize",
                "\(Int(contentSize.width))x\(Int(contentSize.height))",
                "-ApplePersistenceIgnoreState", "YES"
            ]
#else
            setupSnapshot(app)
            // iPad ships landscape App Store screenshots (solitaire is played
            // landscape there); iPhone is portrait-only.
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCUIDevice.shared.orientation = .landscapeLeft
            }
#endif
            app.launchArguments += Self.appearance + ["-screenshotFixture", board]
            app.launch()
            XCTAssertTrue(
                app.windows.firstMatch.waitForExistence(timeout: 10),
                "\(board): app window never appeared"
            )
            // Let load animations and the initial layout settle.
            Thread.sleep(forTimeInterval: 2)

#if os(macOS)
            try captureMacWindow(of: app, named: board)
#else
            snapshot(board)
#endif
            // No explicit terminate: launch() relaunches a running app, and the
            // session tears down the last instance. terminate() flakes on macOS.
        }
    }

#if os(macOS)
    /// Measures the window title-bar height: launches the app with its
    /// content pinned to the reference size and returns how much taller the
    /// window frame is. The probe instance is replaced by the next launch.
    @MainActor
    private func measureTitleBarHeight() throws -> CGFloat {
        let probe = XCUIApplication()
        probe.launchArguments += [
            "-screenshotWindowSize",
            "\(Int(Self.windowSize.width))x\(Int(Self.windowSize.height))",
            "-ApplePersistenceIgnoreState", "YES",
            "-screenshotFixture", Self.boards[0]
        ]
        probe.launch()
        let window = probe.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "probe window never appeared")

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, window.frame.height < Self.windowSize.height {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let titleBarHeight = window.frame.height - Self.windowSize.height
        XCTAssertGreaterThan(titleBarHeight, 0, "probe: no title bar measured")
        XCTAssertLessThan(titleBarHeight, 100, "probe: implausible title-bar height")
        return titleBarHeight
    }

    /// Captures the full app window (title bar and toolbar included) as an
    /// exact-size PNG attachment.
    ///
    /// `XCUIElement.screenshot()` is unreliable for macOS windows (it can
    /// return the entire desktop), so this takes a full-screen capture and
    /// crops it to the window's frame. The window must be frontmost —
    /// anything overlapping it would end up in the crop.
    @MainActor
    private func captureMacWindow(of app: XCUIApplication, named name: String) throws {
        app.activate()
        let window = app.windows.firstMatch

        // Wait for the pinned content size plus measured title bar to land.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline,
              abs(window.frame.width - Self.windowSize.width) > 1
                || abs(window.frame.height - Self.windowSize.height) > 1 {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let frame = window.frame
        XCTAssertEqual(frame.width, Self.windowSize.width, accuracy: 1, "\(name): window never took the pinned size")
        XCTAssertEqual(frame.height, Self.windowSize.height, accuracy: 1, "\(name): window never took the pinned size")

        let screen = try XCTUnwrap(NSScreen.screens.first, "no screen")
        let fullImage = XCUIScreen.main.screenshot().image
        let fullCG = try XCTUnwrap(
            fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
            "\(name): screen capture failed"
        )

        // Window frame is in points with a top-left origin — the same
        // orientation as CGImage rows — so only the display scale applies.
        let scale = CGFloat(fullCG.width) / screen.frame.width
        let crop = CGRect(
            x: frame.minX * scale,
            y: frame.minY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        ).integral
        let cropped = try XCTUnwrap(fullCG.cropping(to: crop), "\(name): crop failed")

        let expected = CGSize(
            width: Self.windowSize.width * screen.backingScaleFactor,
            height: Self.windowSize.height * screen.backingScaleFactor
        )
        XCTAssertEqual(CGFloat(cropped.width), expected.width, "\(name): capture is not an exact App Store size")
        XCTAssertEqual(CGFloat(cropped.height), expected.height, "\(name): capture is not an exact App Store size")

        let pngData = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]),
            "\(name): PNG encoding failed"
        )
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
#endif
}
