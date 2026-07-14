import Foundation

/// A staged mid-game board for App Store screenshots.
struct ScreenshotFixture: Identifiable, Hashable {
    /// Bundle resource name of the `SavedGamePayload` JSON, and the screenshot
    /// file name the capture UI test emits.
    let name: String
    /// Human-readable description of the board.
    let title: String

    var id: String { name }
}

/// Staged boards for App Store screenshots.
///
/// Launching with `-screenshotFixture <name>` restores the named board instead
/// of the saved game (DEBUG builds only). `ScreenshotCaptureUITests` does this
/// for every bundled board and captures the screenshots; run it via
/// `fastlane screenshots`. Loading suppresses autosave for the rest of the
/// session so a screenshot run can't clobber a real in-progress game, and
/// payloads carry `hasStartedTrackedGame: false` so statistics stay untouched.
///
/// Fixtures are generated — not hand-edited — by `ScreenshotFixtureTests`, which
/// plays a seeded deal forward with the hint planner; hand-edited payloads risk
/// failing the persistence validity gate and silently falling back to a new deal.
enum ScreenshotFixtures {
    static let launchArgument = "-screenshotFixture"

    /// Boards shipped in the app bundle; validated by `ScreenshotFixtureTests`.
    /// One entry per App Store screenshot, in store order.
    static let bundled: [ScreenshotFixture] = [
        ScreenshotFixture(name: "klondike-draw3", title: "Klondike – Draw 3"),
        ScreenshotFixture(name: "freecell", title: "FreeCell – fresh deal"),
        ScreenshotFixture(name: "yukon", title: "Yukon – fresh deal"),
        ScreenshotFixture(name: "spider", title: "Spider – 2 suits"),
        ScreenshotFixture(name: "pyramid", title: "Pyramid – fresh deal"),
        ScreenshotFixture(name: "tripeaks", title: "TriPeaks – fresh deal"),
        ScreenshotFixture(name: "golf", title: "Golf – fresh deal"),
        ScreenshotFixture(name: "fortythieves", title: "Forty Thieves – fresh deal"),
        ScreenshotFixture(name: "scorpion", title: "Scorpion – fresh deal"),
        ScreenshotFixture(name: "canfield", title: "Canfield – fresh deal")
    ]

    static func payloadFromLaunchArguments() -> SavedGamePayload? {
        guard let name = value(after: launchArgument) else { return nil }
        return payload(named: name, in: .main)
    }

    /// Content-area size requested via `-screenshotWindowSize <width>x<height>`
    /// (in points). The app scene pins its content to this size (see
    /// `ComputerSolitaireApp`); the Mac capture uses 1440x900 so the content
    /// screenshot comes out at 2880x1800 pixels on a Retina display — an
    /// exact Mac App Store size.
    static var requestedWindowSize: CGSize? {
        size(after: "-screenshotWindowSize")
    }

    private static func size(after flag: String) -> CGSize? {
        guard let raw = value(after: flag) else { return nil }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: flag),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1]
    }

    static func payload(named name: String, in bundle: Bundle) -> SavedGamePayload? {
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedGamePayload.self, from: data)
    }
}
