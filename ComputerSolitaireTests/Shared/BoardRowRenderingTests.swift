import CoreGraphics
import ImageIO
import SwiftUI
import XCTest
@testable import Computer_Solitaire

@MainActor
final class BoardRowRenderingTests: XCTestCase {
    func testAsymmetricDivisionStaysClearInBothLayoutDirections() throws {
        let size = CGSize(width: 850, height: 626)
        let physicalDivision = CGRect(x: 200, y: 0, width: 40, height: size.height)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            // GeometryProxy supplies logical coordinates by default. The same
            // physical hinge therefore arrives mirrored in an RTL environment.
            let logicalDivision = direction == .leftToRight ? physicalDivision
                : CGRect(x: size.width - physicalDivision.maxX, y: 0,
                         width: physicalDivision.width, height: size.height)
            for count in [7, 8, 10] {
                let metrics = Layout.metrics(for: size, tableauColumnCount: count,
                                             division: logicalDivision)
                let row = BoardRow(spacing: metrics.columnSpacing) {
                    ForEach(0..<count, id: \.self) { _ in
                        Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0))
                            .frame(width: metrics.cardSize.width, height: 40)
                    }
                }
                .environment(\.boardColumns, metrics.columns)
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(width: size.width, height: 40, alignment: .topLeading)
                .environment(\.layoutDirection, direction)
                let renderer = ImageRenderer(content: row)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                let pixels = try redPixels(in: image, row: 20)
                let occupied = pixels.indices.filter { pixels[$0] }
                XCTAssertFalse(occupied.isEmpty)
                XCTAssertTrue(occupied.contains { $0 < Int(physicalDivision.minX) })
                XCTAssertTrue(occupied.contains { $0 >= Int(physicalDivision.maxX) })
                XCTAssertFalse((Int(physicalDivision.minX)..<Int(physicalDivision.maxX))
                    .contains { pixels[$0] }, "\(direction), \(count) columns cover the hinge")
                let starts = pixels.indices.filter { pixels[$0] && ($0 == 0 || !pixels[$0 - 1]) }
                XCTAssertEqual(starts.count, count, "Every pile must remain distinct")
            }
        }
    }

    func testSharedBoardsRenderAtNarrowAndHeightLimitedSizes() throws {
        for fixture in ["klondike-draw3", "freecell", "spider", "canfield"] {
            let session = SolitaireViewModel()
            XCTAssertTrue(session.restore(from: try XCTUnwrap(ScreenshotFixtures.payload(
                named: fixture, in: Bundle(for: SolitaireViewModel.self)))))
            for size in [CGSize(width: 360, height: 700), CGSize(width: 850, height: 626),
                         CGSize(width: 1400, height: 420)] {
                try attach(SharedColumnBoardSample(session: session, size: size),
                           name: "\(fixture)-\(Int(size.width))x\(Int(size.height))")
            }
        }
    }

    func testHeaderOcclusionRendersWithoutMovingThePlayArea() throws {
        let session = SolitaireViewModel()
        XCTAssertTrue(session.restore(from: try XCTUnwrap(ScreenshotFixtures.payload(
            named: "freecell", in: Bundle(for: SolitaireViewModel.self)))))
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            try attach(SharedColumnBoardSample(session: session, size: CGSize(width: 850, height: 626),
                camera: CGRect(x: 380, y: 0, width: 60, height: 60))
                .environment(\.layoutDirection, direction), name: "header-camera-\(direction)")
        }
    }

    private func attach(_ content: some View, name: String) throws {
        let renderer = ImageRenderer(content: content.environment(\.cardStyle, .simple)
            .environment(\.colorScheme, .dark).background { TableBackground() })
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let attachment = XCTAttachment(data: data as Data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func redPixels(in image: CGImage, row: Int) throws -> [Bool] {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<image.width).map { x in
            let offset = row * context.bytesPerRow + x * 4
            return bytes[offset] > 200 && bytes[offset + 1] < 50 && bytes[offset + 2] < 50
        }
    }
}

private struct SharedColumnBoardSample: View {
    let session: SolitaireViewModel
    let size: CGSize
    var camera: CGRect?
    private let drag: (DragOrigin) -> AnyGesture<DragGesture.Value> = { _ in AnyGesture(DragGesture()) }
    private let token = UUID()

    var body: some View {
        let metrics = Computer_Solitaire.Layout.metrics(for: size,
            tableauColumnCount: session.gameVariant.boardColumnCount, headerHeight: 82,
            headerOcclusions: camera.map { [$0] } ?? [], variant: session.gameVariant)
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            HeaderView(gameTitle: session.gameVariant.title, gameQualifier: nil,
                movesCount: session.movesCount, elapsedSeconds: 60, score: session.score,
                onGameTitleTapped: {}, onScoreTapped: {})
                .frame(width: metrics.headerFrame.width)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, metrics.headerFrame.minX)
            TopRowView(session: session, board: session.topRowSnapshot, selection: session.selectionSnapshot,
                cardSize: metrics.cardSize, columnSpacing: metrics.columnSpacing,
                wasteFanSpacing: metrics.wasteFanSpacing, activeTarget: nil, hintedTarget: nil,
                isStockHinted: false, isWasteHinted: false, hintHighlightOpacity: 0,
                isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [], hintedCardIDs: [],
                hintWiggleToken: token, drawingCardIDs: [], fanProgress: [:], dragGesture: drag)
            if session.gameVariant == .canfield {
                CanfieldBoardRowView(session: session, reserve: session.state.reserve, tableau: session.state.tableau,
                    selection: session.selectionSnapshot, cardSize: metrics.cardSize,
                    columnSpacing: metrics.columnSpacing, faceDownOffset: metrics.tableauFaceDownOffset,
                    faceUpOffset: metrics.tableauFaceUpOffset, maxPileHeight: metrics.tableauMaxHeight,
                    activeTarget: nil, hintedTarget: nil, hintHighlightOpacity: 0,
                    isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [], hintedCardIDs: [],
                    hintWiggleToken: token, dragGesture: drag)
            } else {
                TableauRowView(session: session, tableau: session.state.tableau, variant: session.gameVariant,
                    selection: session.selectionSnapshot, cardSize: metrics.cardSize,
                    columnSpacing: metrics.columnSpacing, faceDownOffset: metrics.tableauFaceDownOffset,
                    faceUpOffset: metrics.tableauFaceUpOffset, maxPileHeight: metrics.tableauMaxHeight,
                    activeTarget: nil, hintedTarget: nil, hintHighlightOpacity: 0,
                    isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [], hintedCardIDs: [],
                    hintWiggleToken: token, dragGesture: drag)
            }
            Spacer(minLength: 0)
        }
        .environment(\.boardColumns, metrics.columns)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
