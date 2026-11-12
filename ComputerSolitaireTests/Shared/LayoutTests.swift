import XCTest
@testable import Computer_Solitaire

@MainActor
final class LayoutTests: XCTestCase {
    func testFormationCenteringRespectsOrientationAndTabletop() {
        for variant in GameVariant.allCases {
            let landscape = CGSize(width: 869, height: 669)
            let metrics = Layout.metrics(for: landscape, variant: variant)
            XCTAssertEqual(metrics.formationAreaHeight != nil, variant == .pyramid)
            XCTAssertNil(Layout.metrics(for: CGSize(width: 626, height: 850), variant: variant).formationAreaHeight)
            XCTAssertNil(Layout.metrics(for: landscape,
                rowDivision: CGRect(x: 0, y: 320, width: 869, height: 40), variant: variant).formationAreaHeight)
            XCTAssertNil(Layout.metrics(for: landscape, variant: variant, separatesDrawPiles: true).formationAreaHeight)
        }
    }

    func testWideBoardKeepsReadableCardsAndBalancedMargins() {
        let metrics = Layout.metrics(for: CGSize(width: 850, height: 626), headerHeight: 82)
        XCTAssertGreaterThanOrEqual(metrics.cardSize.width, 88)
        XCTAssertEqual(metrics.columns.origins.first ?? 0,
                       metrics.columns.width - (metrics.columns.origins.last ?? 0) - metrics.cardSize.width,
                       accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(metrics.tableauMaxHeight, metrics.cardSize.height * 2)
    }

    func testEveryVariantFitsContinuouslyResizedViewports() {
        for variant in GameVariant.allCases {
            for width in stride(from: 300, through: 1400, by: 37) {
                for height in [280, 420, 626, 850, 1100] {
                    let size = CGSize(width: width, height: height)
                    let metrics = Layout.metrics(for: size, tableauColumnCount: variant.boardColumnCount,
                                                 headerHeight: 88, variant: variant)
                    XCTAssertGreaterThan(metrics.cardSize.width, 0, "\(variant), \(size)")
                    XCTAssertEqual(metrics.columns.origins.count, variant.boardColumnCount)
                    for x in metrics.columns.origins {
                        XCTAssertGreaterThanOrEqual(x, 0)
                        XCTAssertLessThanOrEqual(x + metrics.cardSize.width, metrics.columns.width + 0.001)
                    }
                    let usedHeight = 2 * metrics.verticalPadding + 88
                        + (metrics.centersFormationGroup ? 3 : 2) * metrics.rowSpacing
                        + metrics.cardSize.height + metrics.tableauMaxHeight
                    XCTAssertEqual(usedHeight, size.height, accuracy: 0.001)
                }
            }
        }
    }

    func testFoldPreservesColumnCountOrderAndKeepsPilesOutOfDivision() {
        let size = CGSize(width: 850, height: 626)
        for count in [7, 8, 10] {
            for center in [360.0, 425, 475] {
                let division = CGRect(x: center - 20, y: 0, width: 40, height: size.height)
                let metrics = Layout.metrics(for: size, tableauColumnCount: count, division: division)
                let frames = metrics.columns.origins.map {
                    CGRect(x: $0 + metrics.horizontalPadding, y: 0,
                           width: metrics.cardSize.width, height: size.height)
                }
                XCTAssertEqual(frames.count, count)
                XCTAssertTrue(frames.allSatisfy { !$0.intersects(division) })
                for pair in zip(frames, frames.dropFirst()) {
                    XCTAssertLessThan(pair.0.maxX, pair.1.minX)
                }
                XCTAssertTrue(frames.contains { $0.maxX <= division.minX })
                XCTAssertTrue(frames.contains { $0.minX >= division.maxX })
            }
        }
    }

    func testConnectedFormationOccupiesOneUnobstructedRegion() {
        let division = BoardObstruction(frame: CGRect(x: 405, y: 0, width: 40, height: 626), kind: .division)
        let viewport = BoardViewport(size: CGSize(width: 850, height: 626),
                                     obstructions: [division], preservesFormation: true)
        XCTAssertEqual(viewport.frame.width, 850)
        XCTAssertFalse(viewport.formationPanes!.formation.intersects(division.frame))
        XCTAssertFalse(viewport.formationPanes!.draw.intersects(division.frame))
        XCTAssertEqual(viewport.formationPanes?.formation.width, 405)
        XCTAssertNil(viewport.columnDivision)
    }

    func testPyramidBookTargetsFitAsymmetricPanesAndUseLargerCards() throws {
        for variant in [GameVariant.pyramid] {
            for width in [720.0, 869, 1100] {
                for hingeFraction in [0.35, 0.5, 0.65] {
                    let size = CGSize(width: width, height: 669)
                    let hinge = CGRect(x: width * hingeFraction - 20, y: 0, width: 40, height: size.height)
                    let viewport = BoardViewport(size: size,
                        obstructions: [BoardObstruction(frame: hinge, kind: .division)], preservesFormation: true)
                    let panes = try XCTUnwrap(viewport.formationPanes)
                    let metrics = Layout.metrics(for: panes.formation.size,
                        tableauColumnCount: variant.boardColumnCount, headerHeight: 82,
                        variant: variant, separatesDrawPiles: true)
                    let target = panes.drawCardSize(headerHeight: 82, padding: metrics.verticalPadding,
                        spacing: metrics.rowSpacing, hasDiscard: variant == .pyramid)
                    XCTAssertGreaterThanOrEqual(target.width, 44)
                    XCTAssertGreaterThan(target.width, metrics.cardSize.width)
                    XCTAssertLessThanOrEqual(target.width * 2 + FormationDrawLayout.columnGap,
                                             panes.draw.width - metrics.verticalPadding * 2 + 0.001)
                    XCTAssertFalse(panes.formation.intersects(hinge))
                    XCTAssertFalse(panes.draw.intersects(hinge))
                    XCTAssertEqual(metrics.tableauMaxHeight + metrics.verticalPadding * 2
                        + 82 + metrics.rowSpacing, size.height, accuracy: 0.001)
                }
            }
        }
    }

    func testTriPeaksBookPreservesContinuousGeometryAndFullCardSize() throws {
        for width in [720.0, 869, 1100] {
            let size = CGSize(width: width, height: 669)
            let flat = Layout.metrics(for: size, tableauColumnCount: 10,
                headerHeight: 82, variant: .tripeaks)
            for hingeFraction in [0.35, 0.5, 0.65] {
                let hinge = CGRect(x: width * hingeFraction - 20, y: 0, width: 40, height: size.height)
                let book = Layout.metrics(for: size, tableauColumnCount: 10,
                    headerHeight: 82, division: hinge, variant: .tripeaks)
                XCTAssertEqual(book.cardSize, flat.cardSize)
                XCTAssertEqual(book.columns, flat.columns)
                XCTAssertEqual(book.tableauMaxHeight, flat.tableauMaxHeight)
                XCTAssertTrue(book.centersFormationGroup)
                XCTAssertFalse(book.headerFrame.offsetBy(dx: book.horizontalPadding, dy: 0).intersects(hinge))
                let frames = (0..<TriPeaksGeometry.cardCount).map { index in
                    CGRect(x: TriPeaksGeometry.columnOffsetUnits(of: index)
                        * (book.cardSize.width + book.columnSpacing) / 2,
                        y: CGFloat(TriPeaksGeometry.row(of: index)) * book.cardSize.height * 0.55,
                        width: book.cardSize.width, height: book.cardSize.height)
                }
                // All eighteen parent cards, including those above shared
                // base cards, must visibly overlap both covering children.
                for index in 0..<18 {
                    let covering = try XCTUnwrap(TriPeaksGeometry.coveringIndices(of: index))
                    XCTAssertTrue(frames[index].intersects(frames[covering.left]))
                    XCTAssertTrue(frames[index].intersects(frames[covering.right]))
                    XCTAssertEqual(frames[index].midX,
                        (frames[covering.left].midX + frames[covering.right].midX) / 2, accuracy: 0.001)
                }
            }
        }
    }

    func testHorizontalFoldRetainsBothRegionsForTopRowAndTableau() {
        let division = BoardObstruction(frame: CGRect(x: 0, y: 430, width: 626, height: 30), kind: .division)
        let viewport = BoardViewport(size: CGSize(width: 626, height: 890),
                                     obstructions: [division], preservesFormation: false)
        XCTAssertEqual(viewport.frame, CGRect(x: 0, y: 0, width: 626, height: 890))
        XCTAssertNil(viewport.columnDivision)
        XCTAssertEqual(viewport.rowDivision, division.frame)
    }

    func testTabletopKeepsTopRowAndEveryTableauOnOppositeSidesOfHinge() {
        for variant in GameVariant.allCases {
            for height in [626.0, 850, 1_100] {
                let size = CGSize(width: 626, height: height)
                let hinge = CGRect(x: 0, y: height / 2 - 20, width: size.width, height: 40)
                let metrics = Layout.metrics(for: size, tableauColumnCount: variant.boardColumnCount,
                                             headerHeight: 88, rowDivision: hinge, variant: variant)
                let topRowBottom = metrics.verticalPadding + 88 + metrics.rowSpacing + metrics.cardSize.height
                let tableauTop = topRowBottom + metrics.rowSpacing + metrics.tableauSeparation
                XCTAssertLessThanOrEqual(topRowBottom, hinge.minY, "\(variant)")
                XCTAssertGreaterThanOrEqual(tableauTop, hinge.maxY, "\(variant)")
                XCTAssertEqual(tableauTop + metrics.tableauMaxHeight + metrics.verticalPadding,
                               height, accuracy: 0.001)
                let minimumDepth: CGFloat = variant == .pyramid ? 2.8 : 2
                XCTAssertGreaterThanOrEqual(metrics.tableauMaxHeight + 0.001,
                                            metrics.cardSize.height * minimumDepth, "\(variant)")
            }
        }
    }

    func testPyramidMinimumOverlapFitsShortViewportWithoutCoveringToolbar() {
        let metrics = Layout.metrics(for: CGSize(width: 626, height: 330),
                                     headerHeight: 88, variant: .pyramid)
        // Pyramid never compresses its six overlapping rows below 30%.
        let formationHeight = metrics.cardSize.height * (1 + 6 * 0.3)
        XCTAssertLessThanOrEqual(formationHeight, metrics.tableauMaxHeight + 0.001)
    }

    func testCameraInPlayingAreaLeavesContinuousPlayingArea() {
        let camera = BoardObstruction(frame: CGRect(x: 400, y: 0, width: 30, height: 130), kind: .occlusion)
        let viewport = BoardViewport(size: CGSize(width: 850, height: 626),
                                     obstructions: [camera], preservesFormation: false)
        XCTAssertFalse(viewport.frame.intersects(camera.frame))
        XCTAssertEqual(viewport.frame, CGRect(x: 0, y: 130, width: 850, height: 496))
    }

    func testHeaderCameraDoesNotResizeOrMoveTheCards() throws {
        let size = CGSize(width: 850, height: 626)
        for variant in GameVariant.allCases {
            for cameraX in [0.0, 400, 800] {
                let camera = CGRect(x: cameraX, y: 0, width: 50, height: 60)
                let viewport = BoardViewport(size: size,
                    obstructions: [BoardObstruction(frame: camera, kind: .occlusion)],
                    preservesFormation: variant == .pyramid, headerHeight: 82)
                XCTAssertEqual(viewport.frame, CGRect(origin: .zero, size: size))
                let plain = Layout.metrics(for: size, tableauColumnCount: variant.boardColumnCount,
                                           headerHeight: 82, variant: variant)
                let protected = Layout.metrics(for: viewport.frame.size,
                    tableauColumnCount: variant.boardColumnCount, headerHeight: 82,
                    headerOcclusions: viewport.headerOcclusions, variant: variant)
                XCTAssertEqual(plain.cardSize, protected.cardSize)
                XCTAssertEqual(plain.columns, protected.columns)
                XCTAssertEqual(plain.tableauMaxHeight, protected.tableauMaxHeight)
                let header = protected.headerFrame.offsetBy(dx: protected.horizontalPadding,
                                                            dy: protected.verticalPadding)
                XCTAssertGreaterThan(header.width, 0)
                XCTAssertFalse(header.intersects(camera))
            }
        }
    }

    func testCameraAndFoldChooseTheLargestUnobstructedHeaderRegion() {
        let size = CGSize(width: 850, height: 626)
        let division = CGRect(x: 405, y: 0, width: 40, height: size.height)
        let cameras = [CGRect(x: 0, y: 0, width: 80, height: 60),
                       CGRect(x: 760, y: 0, width: 90, height: 60)]
        let first = Layout.metrics(for: size, division: division, headerOcclusions: cameras)
        let reversed = Layout.metrics(for: size, division: division, headerOcclusions: cameras.reversed())
        XCTAssertEqual(first, reversed)
        let header = first.headerFrame.offsetBy(dx: first.horizontalPadding, dy: first.verticalPadding)
        XCTAssertEqual(header.minX, 80, accuracy: 0.001)
        XCTAssertEqual(header.maxX, division.minX, accuracy: 0.001)
    }

    func testHeightLimitedPilesKeepBoundedGapsAndAlignedFormationTargets() {
        for variant in GameVariant.allCases {
            let metrics = Layout.metrics(for: CGSize(width: 1400, height: 420),
                tableauColumnCount: variant.boardColumnCount, headerHeight: 82, variant: variant)
            let origins = metrics.columns.origins
            for pair in zip(origins, origins.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.1 - pair.0 - metrics.cardSize.width,
                                         metrics.cardSize.width * 0.4 + 0.001)
            }
            XCTAssertEqual(origins.first ?? 0, metrics.columns.width - (origins.last ?? 0)
                - metrics.cardSize.width, accuracy: 0.001)
            if variant == .pyramid || variant == .tripeaks {
                let formationWidth = CGFloat(variant.boardColumnCount) * metrics.cardSize.width
                    + CGFloat(variant.boardColumnCount - 1) * metrics.columnSpacing
                XCTAssertEqual(origins.first ?? 0, (metrics.columns.width - formationWidth) / 2,
                               accuracy: 0.001, "Draw piles must align with the connected formation")
            }
        }
    }

    func testGameplayOcclusionsKeepTheLargestRegionRegardlessOfOrder() {
        let size = CGSize(width: 850, height: 626)
        let regions = [CGRect(x: 400, y: 0, width: 50, height: 626),
                       CGRect(x: 0, y: 0, width: 380, height: 626)]
        for frames in [regions, Array(regions.reversed())] {
            let viewport = BoardViewport(size: size,
                obstructions: frames.map { BoardObstruction(frame: $0, kind: .occlusion) },
                preservesFormation: false)
            XCTAssertEqual(viewport.frame, CGRect(x: 450, y: 0, width: 400, height: 626))
            XCTAssertTrue(frames.allSatisfy { !viewport.frame.intersects($0) })
        }
        let corners = [CGRect(x: 0, y: 0, width: 70, height: 150),
                       CGRect(x: 780, y: 0, width: 70, height: 140)]
        for frames in [corners, Array(corners.reversed())] {
            let viewport = BoardViewport(size: size,
                obstructions: frames.map { BoardObstruction(frame: $0, kind: .occlusion) },
                preservesFormation: false)
            XCTAssertEqual(viewport.frame, CGRect(x: 70, y: 0, width: 710, height: 626))
        }
    }

    func testClippingForCameraDoesNotChangeTheHingeAxis() {
        let size = CGSize(width: 850, height: 626)
        let viewport = BoardViewport(size: size, obstructions: [
            BoardObstruction(frame: CGRect(x: 405, y: 0, width: 40, height: 626), kind: .division),
            BoardObstruction(frame: CGRect(x: 0, y: 0, width: 850, height: 606), kind: .occlusion)
        ], preservesFormation: false)
        XCTAssertNil(viewport.rowDivision)
        XCTAssertEqual(viewport.columnDivision, CGRect(x: 405, y: 0, width: 40, height: 20))
    }

    func testNestedCanfieldColumnsKeepFoundationAlignmentAcrossFold() {
        let metrics = Layout.metrics(for: CGSize(width: 850, height: 626),
                                     division: CGRect(x: 405, y: 0, width: 40, height: 626))
        let tableau = metrics.columns.suffix(from: 3)
        XCTAssertEqual(tableau.origins.count, 4)
        for index in tableau.origins.indices {
            XCTAssertEqual(tableau.origins[index] + metrics.columns.origins[3],
                           metrics.columns.origins[index + 3], accuracy: 0.001)
        }
    }

    func testInitialFaceUpHeavyDealsKeepRanksExposedInShallowViewports() throws {
        for variant in [GameVariant.freecell, .scorpion, .yukon, .golf] {
            let session = SolitaireViewModel()
            XCTAssertTrue(session.restore(from: try XCTUnwrap(ScreenshotFixtures.payload(
                named: variant.rawValue, in: Bundle(for: SolitaireViewModel.self)))))
            for size in [CGSize(width: 1400, height: 420), CGSize(width: 850, height: 626)] {
                let metrics = Layout.metrics(for: size, tableauColumnCount: variant.boardColumnCount,
                                             headerHeight: 82, variant: variant)
                for pile in session.state.tableau {
                    let offsets = Layout.tableauOffsets(for: pile, cardHeight: metrics.cardSize.height,
                        faceDownOffset: metrics.tableauFaceDownOffset,
                        faceUpOffset: metrics.tableauFaceUpOffset, maxPileHeight: metrics.tableauMaxHeight)
                    for index in pile.indices.dropLast() where pile[index].isFaceUp {
                        XCTAssertGreaterThanOrEqual(offsets[index + 1] - offsets[index],
                            metrics.cardSize.height * 0.3 - 0.001, "\(variant), \(size)")
                    }
                }
            }
        }
    }

    func testDeepPileCompressesHiddenCardsBeforePlayableRanks() {
        let backs = (0..<6).map { _ in Card(suit: .spades, rank: .king, isFaceUp: false) }
        let faces = (0..<7).map { _ in Card(suit: .hearts, rank: .queen, isFaceUp: true) }
        let offsets = Layout.tableauOffsets(for: backs + faces, cardHeight: 140,
                                           faceDownOffset: 22, faceUpOffset: 40, maxPileHeight: 450)
        XCTAssertEqual(offsets.count, 13)
        XCTAssertEqual(offsets.last ?? 0, 310, accuracy: 0.001)
        for index in 6..<12 {
            XCTAssertEqual(offsets[index + 1] - offsets[index], 40, accuracy: 0.001)
        }
        XCTAssertGreaterThan(offsets[1], 0, "Hidden cards retain visible edges")
        XCTAssertLessThan(offsets[1], 22)
    }

    func testPileCompressionPreservesNaturalSpacingAndFitsLongRuns() {
        for faceUp in [false, true] {
            for count in [0, 1, 7, 26, 52] {
                let pile = (0..<count).map { _ in Card(suit: .spades, rank: .king, isFaceUp: faceUp) }
                for height in [140.0, 240, 600, 3000] {
                    let offsets = Layout.tableauOffsets(for: pile, cardHeight: 140,
                        faceDownOffset: 22, faceUpOffset: 40, maxPileHeight: height)
                    XCTAssertEqual(offsets.count, count)
                    XCTAssertLessThanOrEqual((offsets.last ?? 0) + 140, height + 0.001)
                    for pair in zip(offsets, offsets.dropFirst()) {
                        XCTAssertGreaterThanOrEqual(pair.1, pair.0)
                    }
                    if height == 3000 {
                        XCTAssertEqual(offsets.last ?? 0,
                            CGFloat(max(0, count - 1)) * (faceUp ? 40 : 22), accuracy: 0.001)
                    }
                }
            }
        }
    }

    func testMeasuredHeaderHeightReducesTableauBudget() {
        let boardSize = CGSize(width: 1_200, height: 900)
        let shorterHeader = Layout.metrics(
            for: boardSize,
            tableauColumnCount: 7,
            headerHeight: 66
        )
        let tallerHeader = Layout.metrics(
            for: boardSize,
            tableauColumnCount: 7,
            headerHeight: 82
        )

        XCTAssertLessThan(tallerHeader.cardSize.height, shorterHeader.cardSize.height)
        XCTAssertLessThan(tallerHeader.tableauMaxHeight, shorterHeader.tableauMaxHeight)
    }
}
