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

    func testPixelGridSnapsEveryRectangleEdgeToTheDisplayScale() {
        let displayScale: CGFloat = 2
        let grid = PixelGrid(unit: 1.1, displayScale: displayScale)
        let rect = grid.rect(x: 3, y: 7, width: 5, height: 2)

        for edge in [rect.minX, rect.minY, rect.maxX, rect.maxY] {
            XCTAssertEqual(edge * displayScale, (edge * displayScale).rounded())
        }
    }

    func testPixelPipLayoutsStayOnWholeCells() {
        for count in 2...10 {
            let placements = PixelCardArt.pipPlacements(count: count)
            XCTAssertEqual(placements.count, count)

            for placement in placements {
                XCTAssertEqual(placement.x, placement.x.rounded())
                XCTAssertEqual(placement.dy, placement.dy.rounded())
            }
        }
    }

    func testPixelPipSpritesUseAnEvenFootprint() {
        let sprites = [
            PixelSprites.spadePip,
            PixelSprites.heartPip,
            PixelSprites.diamondPip,
            PixelSprites.clubPip,
        ]

        for sprite in sprites {
            XCTAssertEqual(sprite.width, 6)
            XCTAssertEqual(sprite.height, 6)
        }
    }

    func testPixelRoyalSpritesMapOnlyFaceCards() {
        XCTAssertNotNil(PixelSprites.twoWayRoyalHalf(for: .jack))
        XCTAssertNotNil(PixelSprites.twoWayRoyalHalf(for: .queen))
        XCTAssertNotNil(PixelSprites.twoWayRoyalHalf(for: .king))
        XCTAssertNil(PixelSprites.twoWayRoyalHalf(for: .ten))
    }

    func testPixelRoyalColorwaysFollowSuitColor() {
        XCTAssertEqual(PixelRoyalColorway.matching(.hearts), .redSuit)
        XCTAssertEqual(PixelRoyalColorway.matching(.diamonds), .redSuit)
        XCTAssertEqual(PixelRoyalColorway.matching(.spades), .blackSuit)
        XCTAssertEqual(PixelRoyalColorway.matching(.clubs), .blackSuit)
    }

    func testTwoWayPixelRoyalsShareOneSymmetricCenterRow() throws {
        for rank in [Rank.jack, .queen, .king] {
            let half = try XCTUnwrap(PixelSprites.twoWayRoyalHalf(for: rank))
            let centerRow = half.cells[half.height - 1]

            XCTAssertEqual(half.width, 26)
            XCTAssertEqual(half.height * 2 - 1, 45)
            XCTAssertEqual(centerRow, Array(centerRow.reversed()))
        }
    }

    func testTwoWayPixelRoyalsUseTheSameSashBand() throws {
        let sashStarts = [18, 18, 17, 17, 16, 16, 15, 14, 12, 11]
        let sashBand = [
            PixelInk.gold.rawValue,
            PixelInk.robe.rawValue,
            PixelInk.robe.rawValue,
            PixelInk.gold.rawValue,
        ]

        for rank in [Rank.jack, .queen, .king] {
            let half = try XCTUnwrap(PixelSprites.twoWayRoyalHalf(for: rank))

            for (row, start) in sashStarts.enumerated() {
                XCTAssertEqual(
                    Array(half.cells[row + 13][start..<(start + sashBand.count)]),
                    sashBand,
                    "\(rank) sash differs on row \(row + 13)"
                )
            }
        }
    }

    func testPixelStyleReducesTiltWithoutDiscardingItsDirection() {
        XCTAssertEqual(CardTilt.displayAngle(for: 2, style: .pixel), 0.5)
        XCTAssertEqual(CardTilt.displayAngle(for: -2, style: .pixel), -0.5)
        XCTAssertEqual(CardTilt.displayAngle(for: 2, style: .classic), 2)
    }
}
