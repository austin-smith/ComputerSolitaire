import XCTest
@testable import Computer_Solitaire

@MainActor
final class CardStyleTests: XCTestCase {
    func testDefaultStyleIsClassic() {
        XCTAssertEqual(CardStyle.defaultValue, .classic)
        XCTAssertEqual(CardStyle.defaultValue.rawValue, "classic")
    }

    func testOnlyCurrentRawValuesResolveToStyles() {
        XCTAssertEqual(CardStyle(rawValue: "classic"), .classic)
        XCTAssertEqual(CardStyle(rawValue: "simple"), .simple)
        XCTAssertEqual(CardStyle(rawValue: "pixel"), .pixel)
        XCTAssertNil(CardStyle(rawValue: "legacy"))
        XCTAssertNil(CardStyle(rawValue: "default"))
    }

    func testStyleMetadataUsesProductNames() {
        XCTAssertEqual(CardStyle.classic.title, "Classic")
        XCTAssertEqual(CardStyle.classic.subtitle, "Parchment")
        XCTAssertEqual(CardStyle.simple.title, "Simple")
        XCTAssertEqual(CardStyle.simple.subtitle, "Clean")
        XCTAssertEqual(CardStyle.pixel.title, "Pixel")
        XCTAssertEqual(CardStyle.pixel.subtitle, "8-bit Retro")
    }

    func testCardBackColorsResolveFromPersistedIdentifiers() {
        for color in CardBackColor.all {
            XCTAssertEqual(CardBackColor.from(rawValue: color.id), color)
        }
    }

    func testUnknownCardBackColorFallsBackToDefault() {
        XCTAssertEqual(CardBackColor.from(rawValue: "unknown"), .defaultValue)
    }
}
