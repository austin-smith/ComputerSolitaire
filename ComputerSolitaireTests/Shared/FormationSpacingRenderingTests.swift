import CoreGraphics
import ImageIO
import SwiftUI
import XCTest
@testable import Computer_Solitaire

@MainActor
final class FormationSpacingRenderingTests: XCTestCase {
    func testLandscapeKeepsDrawPilesNearTheContinuousFormation() throws {
        let session = try fixture(.tripeaks)
        let size = CGSize(width: 869, height: 669)
        let renderer = ImageRenderer(content: FormationSpacingSample(session: session, size: size,
            tabletop: false, applyAlignment: true))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let bands = try occupiedRowBands(image)
        XCTAssertGreaterThanOrEqual(bands.count, 2)
        let formation = try XCTUnwrap(bands.last)
        let stock = bands[bands.count - 2]
        let gap = formation.lowerBound - stock.upperBound
        XCTAssertGreaterThan(gap, 28, "Waste needs a distinct gap above the first peak")
        XCTAssertLessThan(gap, 38, "Draw piles must remain close to the formation")
        // Compare the visible play group against the header's layout frame;
        // its last opaque text pixel excludes the statistics tile's padding.
        let metrics = Computer_Solitaire.Layout.metrics(for: size, tableauColumnCount: 10,
            headerHeight: 82, variant: .tripeaks)
        let regionTop = metrics.verticalPadding + 82 + metrics.rowSpacing
        let regionBottom = size.height - metrics.verticalPadding
        XCTAssertEqual(CGFloat(stock.lowerBound + formation.upperBound) / 2,
            (regionTop + regionBottom) / 2, accuracy: 2,
            "Center the complete play area below the header")
        try attach(session, size: size, tabletop: false, aligned: false, name: "tripeaks-landscape-before")
        try attach(session, size: size, tabletop: false, aligned: true, name: "tripeaks-landscape-after")
    }

    func testPortraitAndTabletopRendersRemainUnchanged() throws {
        for variant in [GameVariant.pyramid, .tripeaks] {
            let session = try fixture(variant)
            for (size, tabletop) in [(CGSize(width: 626, height: 850), false),
                                      (CGSize(width: 360, height: 700), false),
                                      (CGSize(width: 626, height: 850), true)] {
                var images: [Data] = []
                for aligned in [false, true] {
                    let renderer = ImageRenderer(content: FormationSpacingSample(session: session,
                        size: size, tabletop: tabletop, applyAlignment: aligned))
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.cgImage)
                    images.append(try XCTUnwrap(image.dataProvider?.data) as Data)
                }
                XCTAssertEqual(images[0], images[1], "\(variant), \(size), tabletop=\(tabletop)")
            }
        }
    }

    private func fixture(_ variant: GameVariant) throws -> SolitaireViewModel {
        let session = SolitaireViewModel()
        XCTAssertTrue(session.restore(from: try XCTUnwrap(ScreenshotFixtures.payload(
            named: variant.rawValue, in: Bundle(for: SolitaireViewModel.self)))))
        return session
    }

    private func occupiedRowBands(_ image: CGImage) throws -> [Range<Int>] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var bands: [Range<Int>] = []
        for y in 0..<image.height {
            let occupied = (0..<image.width).contains { bytes[y * context.bytesPerRow + $0 * 4 + 3] > 200 }
            if occupied {
                if let last = bands.last, last.upperBound == y {
                    bands[bands.count - 1] = last.lowerBound..<(y + 1)
                } else { bands.append(y..<(y + 1)) }
            }
        }
        return bands
    }

    private func attach(_ session: SolitaireViewModel, size: CGSize, tabletop: Bool,
                        aligned: Bool, name: String) throws {
        let renderer = ImageRenderer(content: FormationSpacingSample(session: session, size: size,
            tabletop: tabletop, applyAlignment: aligned).background { TableBackground() })
        renderer.scale = 1
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(renderer.cgImage), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let attachment = XCTAttachment(data: data as Data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct FormationSpacingSample: View {
    let session: SolitaireViewModel
    let size: CGSize
    let tabletop: Bool
    let applyAlignment: Bool
    private let token = UUID()
    private let drag: (DragOrigin) -> AnyGesture<DragGesture.Value> = { _ in AnyGesture(DragGesture()) }

    var body: some View {
        let division = tabletop ? CGRect(x: 0, y: size.height / 2 - 20, width: size.width, height: 40) : nil
        let metrics = Computer_Solitaire.Layout.metrics(for: size,
            tableauColumnCount: session.gameVariant.boardColumnCount, headerHeight: 82,
            rowDivision: division, variant: session.gameVariant)
        let surfaceLayout = applyAlignment && metrics.centersFormationGroup
            ? AnyLayout(ContinuousFormationLayout(spacing: metrics.rowSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.rowSpacing))
        surfaceLayout {
            HeaderView(gameTitle: session.gameVariant.title, gameQualifier: nil,
                movesCount: session.movesCount, elapsedSeconds: 10, score: session.score,
                onGameTitleTapped: {}, onScoreTapped: {})
                .frame(width: metrics.headerFrame.width)
                .fixedSize(horizontal: false, vertical: true)
            topRow(metrics: metrics, cardSize: metrics.cardSize)
                .frame(width: metrics.columns.width, alignment: .leading)
                .padding(.bottom, metrics.tableauSeparation)
            formation(metrics: metrics)
                .frame(width: metrics.columns.width, alignment: .leading)
                .frame(height: applyAlignment ? metrics.formationAreaHeight : nil, alignment: .center)
            Spacer(minLength: 0)
        }
        .environment(\.boardColumns, metrics.columns)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.cardStyle, .simple)
        .environment(\.colorScheme, .dark)
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
