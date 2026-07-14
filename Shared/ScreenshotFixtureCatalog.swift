/// A staged board included in the App Store screenshot set.
struct ScreenshotFixture: Identifiable, Hashable {
    /// Bundle resource name and emitted screenshot file name.
    let name: String
    /// Human-readable description of the staged board.
    let title: String

    var id: String { name }
}

/// The single ordered manifest shared by the app and screenshot UI tests.
enum ScreenshotFixtureCatalog {
    static let bundled: [ScreenshotFixture] = [
        ScreenshotFixture(name: "klondike-draw3", title: "Klondike – Draw 3"),
        ScreenshotFixture(name: "freecell", title: "FreeCell"),
        ScreenshotFixture(name: "yukon", title: "Yukon"),
        ScreenshotFixture(name: "spider", title: "Spider – 2 suits"),
        ScreenshotFixture(name: "pyramid", title: "Pyramid"),
        ScreenshotFixture(name: "tripeaks", title: "TriPeaks"),
        ScreenshotFixture(name: "golf", title: "Golf"),
        ScreenshotFixture(name: "fortythieves", title: "Forty Thieves"),
        ScreenshotFixture(name: "scorpion", title: "Scorpion"),
        ScreenshotFixture(name: "canfield", title: "Canfield")
    ]
}
