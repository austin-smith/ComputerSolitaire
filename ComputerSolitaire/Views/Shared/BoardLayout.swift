import SwiftUI

/// Geometry supplied by the system, expressed in the board's logical coordinates.
/// Keeping the value independent of ReservedRegion makes the layout testable on
/// every supported OS; only the API query requires iOS 27.1.
nonisolated struct BoardObstruction: Equatable {
    enum Kind { case division, occlusion }
    var frame: CGRect
    var kind: Kind
}

nonisolated struct BoardViewport: Equatable {
    var frame: CGRect
    var columnDivision: CGRect?
    var rowDivision: CGRect?
    var formationPanes: FormationPanes?
    var headerOcclusions: [CGRect] = []

    init(size: CGSize, obstructions: [BoardObstruction], preservesFormation: Bool,
         headerHeight: CGFloat = 82) {
        let bounds = CGRect(origin: .zero, size: size)
        let occlusions = obstructions.filter { $0.kind == .occlusion }
            .map { $0.frame.intersection(bounds) }.filter { !$0.isNull && !$0.isEmpty }
        let headerBottom = min(20, size.height * 0.025) + headerHeight
        let verticalDivisions = obstructions.filter { $0.kind == .division }
            .map { $0.frame.intersection(bounds) }
            .filter { !$0.isNull && !$0.isEmpty && $0.height > $0.width }
        let headerPane = preservesFormation && !verticalDivisions.isEmpty
            ? FormationPanes(size: size, division: verticalDivisions[0]).formation : bounds
        let headerPadding = min(24, headerPane.width * 0.025)
        let headerBounds = (headerPane.minX + headerPadding)...max(headerPane.minX + headerPadding,
                                                                  headerPane.maxX - headerPadding)
        // A camera confined to the header must not resize all the cards. If an
        // occlusion reaches the playing area, retain one unobstructed board.
        let affectsOnlyHeader = occlusions.allSatisfy { $0.maxY <= headerBottom }
            && Self.widestRange(in: headerBounds, avoiding: occlusions + verticalDivisions) != nil
        let usable = affectsOnlyHeader ? bounds : Self.largestClearRectangle(in: bounds, avoiding: occlusions)
        var division: CGRect?
        var horizontalDivision: CGRect?
        for obstruction in obstructions where obstruction.kind == .division {
            let intersection = usable.intersection(obstruction.frame)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            if obstruction.frame.width >= obstruction.frame.height {
                horizontalDivision = intersection
            } else {
                division = intersection
            }
        }
        frame = usable
        if affectsOnlyHeader { headerOcclusions = occlusions }
        func localDivision(_ region: CGRect?) -> CGRect? {
            guard let region else { return nil }
            let clipped = region.intersection(usable)
            return clipped.isNull || clipped.isEmpty ? nil
                : clipped.offsetBy(dx: -usable.minX, dy: -usable.minY)
        }
        let verticalDivision = localDivision(division)
        columnDivision = preservesFormation ? nil : verticalDivision
        rowDivision = localDivision(horizontalDivision)
        if preservesFormation, let verticalDivision {
            formationPanes = FormationPanes(size: usable.size, division: verticalDivision)
        }

    }

    private static func largestClearRectangle(in bounds: CGRect, avoiding regions: [CGRect]) -> CGRect {
        var candidates = [bounds]
        for region in regions {
            candidates = candidates.flatMap { candidate -> [CGRect] in
                let intersection = candidate.intersection(region)
                guard !intersection.isNull, !intersection.isEmpty else { return [candidate] }
                // Keep every alternative until all occlusions have been
                // considered; choosing now can discard the best final region.
                return [
                    CGRect(x: candidate.minX, y: intersection.maxY, width: candidate.width,
                           height: candidate.maxY - intersection.maxY),
                    CGRect(x: candidate.minX, y: candidate.minY, width: candidate.width,
                           height: intersection.minY - candidate.minY),
                    CGRect(x: candidate.minX, y: candidate.minY, width: intersection.minX - candidate.minX,
                           height: candidate.height),
                    CGRect(x: intersection.maxX, y: candidate.minY, width: candidate.maxX - intersection.maxX,
                           height: candidate.height)
                ].filter { !$0.isEmpty }
            }
        }
        return candidates.max { lhs, rhs in
            let leftArea = lhs.width * lhs.height
            let rightArea = rhs.width * rhs.height
            if leftArea != rightArea { return leftArea < rightArea }
            if lhs.minY != rhs.minY { return lhs.minY > rhs.minY }
            if lhs.minX != rhs.minX { return lhs.minX > rhs.minX }
            return lhs.width < rhs.width
        } ?? CGRect(origin: bounds.origin, size: .zero)
    }

    /// Subtract all reserved intervals before choosing a region, so the result
    /// does not depend on the order in which the system reports them.
    static func widestRange(in bounds: ClosedRange<CGFloat>, avoiding regions: [CGRect]) -> ClosedRange<CGFloat>? {
        var ranges = [bounds]
        for region in regions {
            ranges = ranges.flatMap { range -> [ClosedRange<CGFloat>] in
                let lower = max(range.lowerBound, region.minX)
                let upper = min(range.upperBound, region.maxX)
                guard lower < upper else { return [range] }
                return [range.lowerBound < lower ? range.lowerBound...lower : nil,
                        upper < range.upperBound ? upper...range.upperBound : nil].compactMap { $0 }
            }
        }
        guard let first = ranges.first else { return nil }
        return ranges.dropFirst().reduce(first) { best, candidate in
            candidate.upperBound - candidate.lowerBound > best.upperBound - best.lowerBound ? candidate : best
        }
    }
}

/// Both panes remain available, but the connected formation occupies only one.
/// Coordinates are logical so SwiftUI mirrors the entire composition together.
nonisolated struct FormationPanes: Equatable {
    let formation: CGRect
    let draw: CGRect

    init(size: CGSize, division: CGRect) {
        let leading = CGRect(x: 0, y: 0, width: max(0, division.minX), height: size.height)
        let trailing = CGRect(x: division.maxX, y: 0,
                              width: max(0, size.width - division.maxX), height: size.height)
        (formation, draw) = leading.width >= trailing.width ? (leading, trailing) : (trailing, leading)
    }

    func drawCardSize(headerHeight: CGFloat, padding: CGFloat, spacing: CGFloat,
                      hasDiscard: Bool) -> CGSize {
        let widthFit = max(0, (draw.width - padding * 2 - FormationDrawLayout.columnGap) / 2)
        let heightFit = max(0, (draw.height - padding * 2 - headerHeight - spacing
            - (hasDiscard ? FormationDrawLayout.rowGap : 0)) / (hasDiscard ? 2 : 1)) / 1.45
        let width = min(96, widthFit, heightFit)
        return CGSize(width: width, height: width * 1.45)
    }
}

/// AnyLayout keeps header, draw piles and formation alive when the pose changes.
/// Its four children are the same header, top row, tableau and spacer as the
/// ordinary vertical board layout.
struct BookFormationLayout: SwiftUI.Layout {
    let panes: FormationPanes
    let horizontalPadding: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentY = bounds.minY + sizes[0].height + spacing
        subviews[0].place(at: CGPoint(x: bounds.minX + panes.formation.minX, y: bounds.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(sizes[0]))
        subviews[1].place(at: CGPoint(x: bounds.minX + panes.draw.midX - horizontalPadding - sizes[1].width / 2,
                                     y: contentY),
                          anchor: .topLeading, proposal: ProposedViewSize(sizes[1]))
        subviews[2].place(at: CGPoint(x: bounds.minX + panes.formation.minX, y: contentY),
                          anchor: .topLeading, proposal: ProposedViewSize(sizes[2]))
        subviews[3].place(at: CGPoint(x: bounds.minX, y: bounds.maxY),
                          anchor: .topLeading, proposal: .zero)
    }
}

/// Keeps stock, waste and the connected formation together below the header.
/// The existing four board children retain their identities across layouts.
struct ContinuousFormationLayout: SwiftUI.Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentTop = bounds.minY + sizes[0].height + spacing
        let groupHeight = sizes[1].height + spacing * 2 + sizes[2].height
        let groupTop = contentTop + max(0, (bounds.maxY - contentTop - groupHeight) / 2)
        let positions = [bounds.minY, groupTop, groupTop + sizes[1].height + spacing * 2]
        for index in 0..<3 {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: positions[index]),
                anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
        }
        subviews[3].place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .topLeading, proposal: .zero)
    }
}

enum Layout {
    private static let faceUpSpreadFraction: CGFloat = 0.3
    private static let minimumFaceDownSpreadFraction: CGFloat = 0.04

    static func tableauOffsets(for pile: [Card], cardHeight: CGFloat,
                               faceDownOffset: CGFloat, faceUpOffset: CGFloat,
                               maxPileHeight: CGFloat) -> [CGFloat] {
        guard !pile.isEmpty else { return [] }
        let coveredCards = pile.dropLast()
        let downCount = CGFloat(coveredCards.filter { !$0.isFaceUp }.count)
        let upCount = CGFloat(coveredCards.count) - downCount
        let available = max(0, maxPileHeight - cardHeight)
        // Preserve readable face-up ranks before spending space on card backs.
        // Retain a small visible edge for each hidden card; if even that cannot
        // fit, compress the remaining spread together to stay inside the board.
        let minimumDownOffset = min(faceDownOffset, cardHeight * minimumFaceDownSpreadFraction)
        let downOffset = downCount > 0
            ? min(faceDownOffset, max(minimumDownOffset, (available - upCount * faceUpOffset) / downCount))
            : faceDownOffset
        let spread = downCount * downOffset + upCount * faceUpOffset
        let scale = spread > 0 ? min(1, available / spread) : 1
        var offsets: [CGFloat] = [0]
        for card in coveredCards {
            offsets.append((offsets.last ?? 0) + (card.isFaceUp ? faceUpOffset : downOffset) * scale)
        }
        return offsets
    }

    struct Metrics: Equatable {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let rowSpacing: CGFloat
        let columnSpacing: CGFloat
        let cardSize: CGSize
        let tableauFaceDownOffset: CGFloat
        let tableauFaceUpOffset: CGFloat
        let wasteFanSpacing: CGFloat
        let tableauMaxHeight: CGFloat
        let formationAreaHeight: CGFloat?
        let tableauSeparation: CGFloat
        let columns: BoardColumns
        let centersFormationGroup: Bool
        let headerFrame: CGRect
    }

    static func metrics(
        for boardSize: CGSize,
        tableauColumnCount: Int = 7,
        headerHeight: CGFloat = HeaderView.estimatedHeight,
        division: CGRect? = nil,
        rowDivision: CGRect? = nil,
        headerOcclusions: [CGRect] = [],
        variant: GameVariant = .klondike,
        separatesDrawPiles: Bool = false
    ) -> Metrics {
        let count = max(1, tableauColumnCount)
        let width = max(0, boardSize.width)
        let height = max(0, boardSize.height)
        let horizontalPadding = min(24, width * 0.025)
        let verticalPadding = min(20, height * 0.025)
        let rowSpacing = min(20, height * 0.025)
        let contentWidth = max(0, width - horizontalPadding * 2)
        let spacing = min(18, contentWidth / CGFloat(count) * 0.14)
        let gapCount = CGFloat(count - 1)
        var fittedWidth = max(0, (contentWidth - spacing * gapCount) / CGFloat(count))
        let localDivision = division.map { $0.offsetBy(dx: -horizontalPadding, dy: 0) }
        var splitIndex: Int?
        if let localDivision, count > 1, variant != .tripeaks {
            let leftWidth = max(0, localDivision.minX)
            let rightWidth = max(0, contentWidth - localDivision.maxX)
            // Preserve the logical order and choose the division between piles
            // that provides the largest common card size on both sides.
            let candidates = (1..<count).map { leftCount in
                let rightCount = count - leftCount
                let leftFit = (leftWidth - CGFloat(leftCount - 1) * spacing) / CGFloat(leftCount)
                let rightFit = (rightWidth - CGFloat(rightCount - 1) * spacing) / CGFloat(rightCount)
                return (leftCount, min(leftFit, rightFit))
            }
            if let best = candidates.max(by: { $0.1 < $1.1 }) {
                splitIndex = best.0
                fittedWidth = max(0, min(fittedWidth, best.1))
            }
        }
        // A stable readable depth, independent of moves, prevents the cards
        // from changing size every time a player adds to a pile.
        let depth: CGFloat
        switch variant {
        case .pyramid: depth = 2 + 6 * 0.45
        case .tripeaks: depth = 2 + 3 * 0.55
        case .golf: depth = 2 + 4 * 0.28
        default: depth = 2 + 4 * 0.16 + 10 * 0.28
        }
        // Budget for readable ranks in the initial deal, not just two full
        // card rectangles. Face-up-heavy games otherwise fit geometrically
        // while their overlapping cards hide the information needed to play.
        let minimumTableauDepth: CGFloat
        switch variant {
        case .freecell, .scorpion: minimumTableauDepth = 1 + 6 * faceUpSpreadFraction
        case .yukon: minimumTableauDepth = 1 + 6 * minimumFaceDownSpreadFraction + 4 * faceUpSpreadFraction
        case .golf: minimumTableauDepth = 1 + 4 * faceUpSpreadFraction
        case .pyramid: minimumTableauDepth = 2.8
        default: minimumTableauDepth = 2
        }
        let centersFormationGroup = variant == .tripeaks && width > height
            && rowDivision == nil && !separatesDrawPiles
        let remainingHeight = max(0, height - verticalPadding * 2 - headerHeight
            - rowSpacing * (separatesDrawPiles ? 1 : centersFormationGroup ? 3 : 2))
        // Preserve the existing board's readable-card floor when height is
        // scarce. A deep pile compresses its spread instead of shrinking the
        // entire game into a narrow strip on a wide display. The final bound
        // still leaves room for the formation's minimum overlap, including
        // Pyramid's six overlapping rows, within the actual safe-area budget.
        let preferredHeightFit: CGFloat
        let maximumHeightFit: CGFloat
        if let rowDivision {
            // Keep the existing vertical hierarchy: header and top-row piles
            // above the hinge, with the tableau on the lower touch surface.
            let upperCardHeight = max(0, rowDivision.minY - verticalPadding * 2 - headerHeight - rowSpacing)
            let lowerHeight = max(0, height - verticalPadding - rowDivision.maxY - rowSpacing)
            preferredHeightFit = max(88, lowerHeight / ((depth - 1) * 1.45))
            maximumHeightFit = min(upperCardHeight, lowerHeight / minimumTableauDepth) / 1.45
        } else {
            preferredHeightFit = max(88, remainingHeight / ((depth - (separatesDrawPiles ? 1 : 0)) * 1.45))
            maximumHeightFit = remainingHeight / (((separatesDrawPiles ? 0 : 1) + minimumTableauDepth) * 1.45)
        }
        let cardWidth = max(0, min(144, fittedWidth, preferredHeightFit, maximumHeightFit))
        let cardSize = CGSize(width: cardWidth, height: cardWidth * 1.45)
        let naturalTableauY = verticalPadding + headerHeight + rowSpacing * 2 + cardSize.height
        let tableauSeparation = rowDivision.map { max(0, $0.maxY + rowSpacing - naturalTableauY) } ?? 0
        let tableauHeight = max(0, remainingHeight - (separatesDrawPiles ? 0 : cardSize.height) - tableauSeparation)
        var origins = [CGFloat]()
        func appendColumns(count: Int, in range: ClosedRange<CGFloat>) {
            let available = range.upperBound - range.lowerBound
            if count == 1 {
                origins.append(range.lowerBound + max(0, (available - cardWidth) / 2))
            } else {
                // Height-limited cards stay together instead of acquiring
                // card-sized gaps on wide windows. Connected formations use
                // their exact spacing so draw piles share the same columns.
                let maximumGap = variant == .pyramid || variant == .tripeaks
                    ? spacing : max(spacing, cardWidth * 0.4)
                let step = min(cardWidth + maximumGap,
                               max(0, (available - cardWidth) / CGFloat(count - 1)))
                let occupiedWidth = cardWidth + CGFloat(count - 1) * step
                let start = range.lowerBound + max(0, (available - occupiedWidth) / 2)
                origins += (0..<count).map { start + CGFloat($0) * step }
            }
        }
        var headerRange: ClosedRange<CGFloat> = 0...contentWidth
        if let splitIndex, let localDivision {
            let leftEnd = max(0, min(contentWidth, localDivision.minX))
            let rightStart = max(leftEnd, min(contentWidth, localDivision.maxX))
            appendColumns(count: splitIndex, in: 0...leftEnd)
            appendColumns(count: count - splitIndex, in: rightStart...contentWidth)
        } else {
            appendColumns(count: count, in: 0...contentWidth)
        }
        // TriPeaks is continuous game content: its shared base cards must
        // remain under both covering branches, including across a fold.
        // The header still avoids the active division.
        let headerRegions = headerOcclusions.map { $0.offsetBy(dx: -horizontalPadding, dy: 0) }
            + (localDivision.map { [$0] } ?? [])
        headerRange = BoardViewport.widestRange(in: headerRange, avoiding: headerRegions) ?? 0...0
        let faceDownOffset = cardSize.height * 0.16
        let faceUpOffset = min(cardSize.height * 0.4,
            max(cardSize.height * faceUpSpreadFraction, (tableauHeight - cardSize.height - 6 * faceDownOffset) / 12))
        return Metrics(
            horizontalPadding: horizontalPadding, verticalPadding: verticalPadding,
            rowSpacing: rowSpacing, columnSpacing: spacing, cardSize: cardSize,
            tableauFaceDownOffset: faceDownOffset, tableauFaceUpOffset: faceUpOffset,
            wasteFanSpacing: cardWidth * 0.18, tableauMaxHeight: tableauHeight,
            // Fixed-depth formations use the spare height in landscape,
            // center that formation in its available area instead of leaving
            // all surplus height below it and crowding the draw piles above.
            formationAreaHeight: variant == .pyramid
                && width > height && division == nil
                && rowDivision == nil && !separatesDrawPiles
                ? tableauHeight : nil,
            tableauSeparation: tableauSeparation,
            columns: BoardColumns(origins: origins, cardWidth: cardWidth, width: contentWidth),
            centersFormationGroup: centersFormationGroup,
            headerFrame: CGRect(x: headerRange.lowerBound, y: 0,
                                width: headerRange.upperBound - headerRange.lowerBound, height: headerHeight)
        )
    }
}

nonisolated struct BoardColumns: Equatable {
    var origins: [CGFloat] = []
    var cardWidth: CGFloat = 0
    var width: CGFloat = 0

    func suffix(from index: Int) -> BoardColumns {
        guard origins.indices.contains(index) else { return BoardColumns() }
        let start = origins[index]
        return BoardColumns(origins: origins.dropFirst(index).map { $0 - start },
                            cardWidth: cardWidth, width: width - start)
    }
}

extension EnvironmentValues {
    @Entry var boardColumns = BoardColumns()
    @Entry var separatesFormationDrawPiles = false
}

private nonisolated struct BoardColumnSpanKey: LayoutValueKey {
    static let defaultValue = 1
}

extension View {
    func boardColumnSpan(_ count: Int) -> some View {
        layoutValue(key: BoardColumnSpanKey.self, value: count)
    }
}

/// Places the same subviews at measured column origins without recreating them
/// when a division becomes active. Preferences therefore measure actual layout
/// frames, including the gap, for both dragging and animation.
struct BoardRow<Content: View>: View {
    @Environment(\.boardColumns) private var columns
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        BoardRowLayout(columns: columns, spacing: spacing) { content }
    }
}

private struct BoardRowLayout: SwiftUI.Layout {
    let columns: BoardColumns
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: columns.origins.isEmpty
            ? sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, sizes.count - 1)) * spacing
            : columns.width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var index = 0
        var fallbackX: CGFloat = 0
        for subview in subviews {
            let span = max(1, subview[BoardColumnSpanKey.self])
            let size = subview.sizeThatFits(.unspecified)
            let x = columns.origins.indices.contains(index) ? columns.origins[index] : fallbackX
            let endIndex = index + span - 1
            let width = columns.origins.indices.contains(endIndex)
                ? columns.origins[endIndex] + columns.cardWidth - x : size.width
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: size.height))
            fallbackX = x + width + spacing
            index += span
        }
    }
}

extension GeometryProxy {
    var boardObstructions: [BoardObstruction] {
#if os(iOS)
        if #available(iOS 27.1, *) {
            return [ReservedRegion.Kind.division, .occlusion].flatMap { kind in
                // Match SwiftUI Layout's automatic right-to-left mirroring.
                reservedRegions(kind: kind).map { region in
                    // The system frame already includes the region's margins.
                    return BoardObstruction(
                        frame: region.frame,
                        kind: kind == .division ? .division : .occlusion
                    )
                }
            }
        }
#endif
        return []
    }
}

struct BoardLayoutState: Equatable {
    let viewportSize: CGSize
    let viewport: BoardViewport
    let metrics: Layout.Metrics
}

/// The same stock, waste and optional discard move between the ordinary row
/// and the book pane. No duplicated controls or changed interaction semantics.
struct FormationDrawRow<Content: View>: View {
    @Environment(\.boardColumns) private var columns
    @Environment(\.separatesFormationDrawPiles) private var separated
    let spacing: CGFloat
    let columnCount: Int
    @ViewBuilder var content: Content

    var body: some View {
        FormationDrawLayout(columns: columns, spacing: spacing, columnCount: columnCount, separated: separated) { content }
    }
}

struct FormationDrawLayout: SwiftUI.Layout {
    nonisolated static let columnGap: CGFloat = 20
    nonisolated static let rowGap: CGFloat = 24
    let columns: BoardColumns
    let spacing: CGFloat
    let columnCount: Int
    let separated: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let card = sizes.first ?? .zero
        if separated {
            return CGSize(width: card.width * 2 + Self.columnGap,
                          height: card.height * (sizes.count > 2 ? 2 : 1)
                            + (sizes.count > 2 ? Self.rowGap : 0))
        }
        return CGSize(width: columns.origins.isEmpty
            ? card.width * CGFloat(columnCount) + spacing * CGFloat(columnCount - 1) : columns.width,
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let column = index == 2 ? max(0, columns.origins.count - 1) : index
            let x = separated ? (index == 1 ? size.width + Self.columnGap : 0)
                : (columns.origins.indices.contains(column)
                   ? columns.origins[column] : CGFloat(index == 2 ? 6 : index) * (size.width + spacing))
            let y = separated && index == 2 ? size.height + Self.rowGap : 0
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                          anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}
