import SwiftUI
import XCTest
@testable import Computer_Solitaire

@MainActor
final class AdaptivePresentationTests: XCTestCase {
#if os(iOS)
    func testRulesAndScoringFitsTheProposedWidth() throws {
        for section in GameGuideView.Section.allCases {
            for width in [300.0, 360, 440, 626, 850] {
                let renderer = ImageRenderer(content: GameGuideView(initialSection: section))
                renderer.proposedSize = ProposedViewSize(width: width, height: 600)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertLessThanOrEqual(image.width, Int(width), "\(section), width \(width)")
                XCTAssertGreaterThan(image.width, 0)
            }
        }
    }
#endif
}
