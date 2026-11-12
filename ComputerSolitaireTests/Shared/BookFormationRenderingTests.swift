import CoreGraphics
import ImageIO
import SwiftUI
import XCTest
@testable import Computer_Solitaire

@MainActor
final class BookFormationRenderingTests: XCTestCase {
    func testBookCompositionsRenderInBothDirections() throws {
        for variant in [GameVariant.pyramid, .tripeaks] {
            let session = SolitaireViewModel()
            let payload = try XCTUnwrap(ScreenshotFixtures.payload(named: variant.rawValue,
                in: Bundle(for: SolitaireViewModel.self)))
            XCTAssertTrue(session.restore(from: payload))
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let sample = BookFormationSample(session: session, direction: direction)
                    .environment(\.cardStyle, .simple)
                    .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: sample)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                let columns = try opaquePixelsPerColumn(in: image)
                if variant == .pyramid {
                    XCTAssertEqual(columns[457..<494].reduce(0, +), 0, "\(variant), \(direction)")
                } else {
                    // The connected TriPeaks formation intentionally spans the
                    // crease; splitting shared base cards breaks its meaning.
                    XCTAssertGreaterThan(columns[457..<494].reduce(0, +), 0)
                }
                XCTAssertGreaterThan(columns[..<455].reduce(0, +), 10_000)
                XCTAssertGreaterThan(columns[496...].reduce(0, +), 10_000)
                // Keep the actual production-view render available for review.
                let preview = ImageRenderer(content: sample.background { TableBackground() })
                preview.scale = 2
                let data = NSMutableData()
                let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data,
                    "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, try XCTUnwrap(preview.cgImage), nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                let attachment = XCTAttachment(data: data as Data, uniformTypeIdentifier: "public.png")
                attachment.name = "\(variant.rawValue)-book-\(direction == .leftToRight ? "ltr" : "rtl")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testUndoFlightReachesTheSmallerFormationCardSize() throws {
        let card = try XCTUnwrap(GameStateFixtures.seededTriPeaksDeal(seed: 5).waste.first)
        let destination = CGRect(x: 200, y: 50, width: 38, height: 55.1)
        let item = UndoAnimationItem(id: card.id, card: card, endFaceUp: true,
            startFrame: CGRect(x: 20, y: 20, width: 96, height: 139.2), endFrame: destination)
        let renderer = ImageRenderer(content: UndoOverlayView(items: [item], progress: 1)
            .frame(width: 300, height: 180)
            .environment(\.cardStyle, .simple))
        renderer.scale = 1
        let columns = try opaquePixelsPerColumn(in: XCTUnwrap(renderer.cgImage))
        let occupied = columns.indices.filter { columns[$0] > 0 }
        XCTAssertEqual(occupied.first, 200)
        XCTAssertEqual(occupied.last, 237)
    }

    private func opaquePixelsPerColumn(in image: CGImage) throws -> [Int] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<image.width).map { x in
            (0..<image.height).reduce(0) { count, y in
                count + (bytes[y * context.bytesPerRow + x * 4 + 3] > 200 ? 1 : 0)
            }
        }
    }
}

private struct BookFormationSample: View {
    let session: SolitaireViewModel
    let direction: LayoutDirection
    private let size = CGSize(width: 869, height: 669)
    private let division = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    private let token = UUID()
    private let drag: (DragOrigin) -> AnyGesture<DragGesture.Value> = { _ in AnyGesture(DragGesture()) }

    var body: some View {
        let logicalDivision = direction == .leftToRight ? division
            : CGRect(x: size.width - division.maxX, y: 0, width: division.width, height: size.height)
        let viewport = BoardViewport(size: size,
            obstructions: [BoardObstruction(frame: logicalDivision, kind: .division)], preservesFormation: session.gameVariant == .pyramid)
        let panes = viewport.formationPanes
        let metrics = Layout.metrics(for: panes?.formation.size ?? viewport.frame.size,
            tableauColumnCount: session.gameVariant.boardColumnCount, headerHeight: 82,
            division: viewport.columnDivision, variant: session.gameVariant,
            separatesDrawPiles: panes != nil)
        let drawSize = panes?.drawCardSize(headerHeight: 82, padding: metrics.verticalPadding,
            spacing: metrics.rowSpacing, hasDiscard: session.gameVariant == .pyramid) ?? metrics.cardSize
        let surfaceLayout = panes.map {
            AnyLayout(BookFormationLayout(panes: $0, horizontalPadding: metrics.horizontalPadding,
                                          spacing: metrics.rowSpacing))
        } ?? (metrics.centersFormationGroup
            ? AnyLayout(ContinuousFormationLayout(spacing: metrics.rowSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.rowSpacing)))
        surfaceLayout {
            HeaderView(gameTitle: session.gameVariant.title, gameQualifier: nil,
                movesCount: session.movesCount, elapsedSeconds: 10, score: session.score,
                onGameTitleTapped: {}, onScoreTapped: {})
                .frame(width: metrics.headerFrame.width)
                .padding(.leading, metrics.headerFrame.minX)
                .fixedSize(horizontal: false, vertical: true)
            topRow(metrics: metrics, cardSize: drawSize)
                .frame(width: panes == nil ? metrics.columns.width
                    : drawSize.width * 2 + FormationDrawLayout.columnGap, alignment: .leading)
            formation(metrics: metrics)
                .frame(height: metrics.formationAreaHeight, alignment: .center)
                .frame(width: metrics.columns.width, alignment: .leading)
            Spacer(minLength: 0)
        }
        .environment(\.boardColumns, metrics.columns)
        .environment(\.separatesFormationDrawPiles, panes != nil)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.layoutDirection, direction)
    }

    private func topRow(metrics: Computer_Solitaire.Layout.Metrics, cardSize: CGSize) -> some View {
        TopRowView(session: session, board: session.topRowSnapshot,
            selection: session.selectionSnapshot, cardSize: cardSize,
            columnSpacing: metrics.columnSpacing, wasteFanSpacing: metrics.wasteFanSpacing,
            activeTarget: nil, hintedTarget: nil, isStockHinted: false, isWasteHinted: false,
            hintHighlightOpacity: 0, isCardTiltEnabled: false, cardTilts: .constant([:]),
            hiddenCardIDs: [], hintedCardIDs: [], hintWiggleToken: token, drawingCardIDs: [],
            fanProgress: [:], dragGesture: drag)
            .environment(\.boardColumns, metrics.columns)
    }

    @ViewBuilder private func formation(metrics: Computer_Solitaire.Layout.Metrics) -> some View {
        if session.gameVariant == .pyramid {
            PyramidBoardView(session: session, pyramid: session.state.pyramid,
                selection: session.selectionSnapshot, cardSize: metrics.cardSize,
                columnSpacing: metrics.columnSpacing, maxBoardHeight: metrics.tableauMaxHeight,
                activeTarget: nil, hintedTarget: nil, hintHighlightOpacity: 0,
                isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [],
                hintedCardIDs: [], hintWiggleToken: token, dragGesture: drag)
        } else {
            TriPeaksBoardView(session: session, triPeaks: session.state.triPeaks,
                selection: session.selectionSnapshot, cardSize: metrics.cardSize,
                columnSpacing: metrics.columnSpacing, maxBoardHeight: metrics.tableauMaxHeight,
                isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [],
                hintedCardIDs: [], hintWiggleToken: token, dragGesture: drag)
        }
    }

}
