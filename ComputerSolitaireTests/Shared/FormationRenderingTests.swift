import CoreGraphics
import SwiftUI
import XCTest
@testable import Computer_Solitaire

@MainActor
final class FormationRenderingTests: XCTestCase {
    func testConnectedFormationsRemainVisibleInRightToLeftLayouts() throws {
        for variant in [GameVariant.pyramid, .tripeaks] {
            let session = SolitaireViewModel()
            let payload = try XCTUnwrap(ScreenshotFixtures.payload(named: variant.rawValue,
                in: Bundle(for: SolitaireViewModel.self)))
            XCTAssertTrue(session.restore(from: payload))
            var pixelCounts: [Int] = []
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let renderer = ImageRenderer(content: FormationSample(session: session)
                    .frame(width: 440, height: 450, alignment: .top)
                    .environment(\.cardStyle, .simple)
                    .environment(\.layoutDirection, direction))
                renderer.scale = 1
                pixelCounts.append(try opaquePixelCount(in: XCTUnwrap(renderer.cgImage)))
            }
            XCTAssertGreaterThan(pixelCounts[0], 10_000)
            XCTAssertEqual(Double(pixelCounts[0]), Double(pixelCounts[1]),
                           accuracy: Double(pixelCounts[0]) * 0.01,
                           "\(variant): mirroring must not clip the connected formation")
        }
    }

    private func opaquePixelCount(in image: CGImage) throws -> Int {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).reduce(0) { count, pixel in
            count + (bytes[pixel * 4 + 3] > 200 ? 1 : 0)
        }
    }
}

private struct FormationSample: View {
    let session: SolitaireViewModel
    private let token = UUID()
    private let drag: (DragOrigin) -> AnyGesture<DragGesture.Value> = { _ in AnyGesture(DragGesture()) }

    var body: some View {
        let size = CGSize(width: 36, height: 52.2)
        if session.gameVariant == .pyramid {
            PyramidBoardView(session: session, pyramid: session.state.pyramid,
                selection: session.selectionSnapshot, cardSize: size,
                columnSpacing: 6, maxBoardHeight: 450,
                activeTarget: nil, hintedTarget: nil, hintHighlightOpacity: 0,
                isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [],
                hintedCardIDs: [], hintWiggleToken: token, dragGesture: drag)
        } else {
            TriPeaksBoardView(session: session, triPeaks: session.state.triPeaks,
                selection: session.selectionSnapshot, cardSize: size,
                columnSpacing: 6, maxBoardHeight: 450,
                isCardTiltEnabled: false, cardTilts: .constant([:]), hiddenCardIDs: [],
                hintedCardIDs: [], hintWiggleToken: token, dragGesture: drag)
        }
    }
}
