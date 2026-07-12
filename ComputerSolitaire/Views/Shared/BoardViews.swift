import SwiftUI
import Observation

enum Layout {
    struct Metrics {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let rowSpacing: CGFloat
        let columnSpacing: CGFloat
        let cardSize: CGSize
        let tableauFaceDownOffset: CGFloat
        let tableauFaceUpOffset: CGFloat
        let wasteFanSpacing: CGFloat
        let tableauMaxHeight: CGFloat
    }

    /// Estimated height of HeaderView (stat tiles + padding); only feeds the
    /// tableau-height budget, so an approximation is fine.
    private static let headerHeightEstimate: CGFloat = 66

    /// Worst-case Klondike pile: 6 face-down cards under a full K–A run.
    private static let maxFaceDownGaps: CGFloat = 6
    private static let maxFaceUpGaps: CGFloat = 12

    /// The pile the layout commits to displaying at natural spacing; cards
    /// are sized so this depth fits the board height. The one design knob:
    /// deeper commitment means smaller cards on short screens. Piles deeper
    /// than this compress their spacing as before.
    private static let readableFaceDownGaps: CGFloat = 4
    private static let readableFaceUpGaps: CGFloat = 10

    /// Height-fitting never pushes cards below this width; on screens too
    /// short to honor the readable depth at a usable card size (phone
    /// landscape), spacing compression takes over instead.
    private static let minHeightFittedCardWidth: CGFloat = 88

    /// The largest card whose top row plus a readable-depth pile fit the
    /// board height at natural spacing. Derived from the same chrome and
    /// spacing fractions the layout actually uses, so it holds on any screen.
    private static func heightFittedCardWidth(
        boardHeight: CGFloat,
        verticalPadding: CGFloat,
        rowSpacing: CGFloat,
        faceDownFraction: CGFloat,
        faceUpFraction: CGFloat
    ) -> CGFloat {
        let chrome = (verticalPadding * 2) + headerHeightEstimate + (rowSpacing * 2)
        // Top-row card + pile base card + gaps, in units of card height.
        let heightUnits = 2 + (readableFaceDownGaps * faceDownFraction) + (readableFaceUpGaps * faceUpFraction)
        let cardHeight = (boardHeight - chrome) / heightUnits
        return max(minHeightFittedCardWidth, cardHeight / 1.45)
    }

    static func metrics(
        for boardSize: CGSize,
        isRegularWidth: Bool = false,
        tableauColumnCount: Int = 7
    ) -> Metrics {
        let columnCount = max(1, tableauColumnCount)
        let boardWidth = boardSize.width
#if os(iOS)
        let isCompactBoard = boardWidth <= 430
        let isMediumBoard = boardWidth > 430 && boardWidth < 760
        let isPadLandscape = isRegularWidth && boardSize.width > boardSize.height
        // Eight-column boards (FreeCell) on phones need tighter chrome so the
        // extra column doesn't shrink every card.
        let isDenseBoard = isCompactBoard && columnCount >= 8

        let horizontalPadding: CGFloat = isDenseBoard ? 8 : (isCompactBoard ? 12 : (isMediumBoard ? 14 : 24))
        let verticalPadding: CGFloat = isPadLandscape ? 12 : (isCompactBoard ? 16 : 24)
        let rowSpacing: CGFloat = isPadLandscape ? 16 : (isCompactBoard ? 16 : 24)
        let columnSpacing: CGFloat = isDenseBoard ? 5 : (isCompactBoard ? 8 : (isMediumBoard ? 10 : 18))

        let faceDownFraction: CGFloat = isCompactBoard ? 0.16 : 0.18
        let faceUpFraction: CGFloat = isCompactBoard ? 0.24 : 0.28
        let landscapeOffsetScale: CGFloat = isPadLandscape ? 0.8 : 1

        let usableWidth = max(0, boardWidth - (horizontalPadding * 2))
        let fittedCardWidth = floor((usableWidth - (columnSpacing * CGFloat(columnCount - 1))) / CGFloat(columnCount))
        let maxCardWidth: CGFloat = isPadLandscape ? 112 : (boardWidth < 760 ? 96 : 120)
        let heightFittedWidth = Self.heightFittedCardWidth(
            boardHeight: boardSize.height,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            faceDownFraction: faceDownFraction * landscapeOffsetScale,
            faceUpFraction: faceUpFraction * landscapeOffsetScale
        )
        let cardWidth = max(32, min(maxCardWidth, fittedCardWidth, heightFittedWidth))
        let cardSize = CGSize(width: cardWidth, height: cardWidth * 1.45)

        let tableauMaxHeight = tableauHeightBudget(
            boardHeight: boardSize.height,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            cardHeight: cardSize.height
        )

        let baseFaceDownOffset = max(isCompactBoard ? 10 : 16, cardSize.height * faceDownFraction)
        let baseFaceUpOffset = max(isCompactBoard ? 14 : 22, cardSize.height * faceUpFraction)

        let faceUpOffset: CGFloat
        let faceDownOffset: CGFloat
        if isPadLandscape {
            faceUpOffset = max(22, baseFaceUpOffset * landscapeOffsetScale)
            faceDownOffset = max(14, baseFaceDownOffset * landscapeOffsetScale)
        } else if isCompactBoard && boardSize.height > boardSize.width {
            // Portrait phones have far more height than the width-fitted cards
            // use; spread the worst-case pile into it, capped for readability.
            let fittedFaceUp = (
                tableauMaxHeight - cardSize.height - maxFaceDownGaps * baseFaceDownOffset
            ) / maxFaceUpGaps
            faceUpOffset = min(max(baseFaceUpOffset, fittedFaceUp), cardSize.height * 0.38)
            faceDownOffset = baseFaceDownOffset
        } else {
            faceUpOffset = baseFaceUpOffset
            faceDownOffset = baseFaceDownOffset
        }

        let wasteFanSpacing = cardSize.width * (isCompactBoard ? 0.18 : (isPadLandscape ? 0.2 : 0.25))

        return Metrics(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            columnSpacing: columnSpacing,
            cardSize: cardSize,
            tableauFaceDownOffset: faceDownOffset,
            tableauFaceUpOffset: faceUpOffset,
            wasteFanSpacing: wasteFanSpacing,
            tableauMaxHeight: tableauMaxHeight
        )
#else
        let horizontalPadding = min(24, max(14, boardWidth * 0.018))
        let verticalPadding = min(22, max(14, boardWidth * 0.015))
        let columnSpacing = min(18, max(10, boardWidth * 0.013))
        let rowSpacing = min(22, max(14, columnSpacing + 4))

        let faceDownFraction: CGFloat = 0.18
        let faceUpFraction: CGFloat = 0.26

        let usableWidth = max(0, boardWidth - (horizontalPadding * 2))
        let fittedCardWidth = floor((usableWidth - (columnSpacing * CGFloat(columnCount - 1))) / CGFloat(columnCount))
        let maxCardWidth = min(124, max(88, boardWidth * 0.095))
        let heightFittedWidth = heightFittedCardWidth(
            boardHeight: boardSize.height,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            faceDownFraction: faceDownFraction,
            faceUpFraction: faceUpFraction
        )
        // Floor low enough that 8 FreeCell columns fit at the minimum window
        // width, which only accommodates 7 Klondike columns at 52pt.
        let cardWidth = max(40, min(maxCardWidth, fittedCardWidth, heightFittedWidth))
        let cardSize = CGSize(width: cardWidth, height: cardWidth * 1.45)

        let tableauMaxHeight = tableauHeightBudget(
            boardHeight: boardSize.height,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            cardHeight: cardSize.height
        )

        let faceDownOffset = max(13, cardSize.height * faceDownFraction)
        let faceUpOffset = max(18, cardSize.height * faceUpFraction)
        let wasteFanSpacing = cardSize.width * (boardWidth < 760 ? 0.2 : 0.25)

        return Metrics(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            columnSpacing: columnSpacing,
            cardSize: cardSize,
            tableauFaceDownOffset: faceDownOffset,
            tableauFaceUpOffset: faceUpOffset,
            wasteFanSpacing: wasteFanSpacing,
            tableauMaxHeight: tableauMaxHeight
        )
#endif
    }

    private static func tableauHeightBudget(
        boardHeight: CGFloat,
        verticalPadding: CGFloat,
        rowSpacing: CGFloat,
        cardHeight: CGFloat
    ) -> CGFloat {
        let chrome = (verticalPadding * 2) + headerHeightEstimate + (rowSpacing * 2) + cardHeight
        return max(cardHeight * 2, boardHeight - chrome)
    }
}

struct HeaderView: View {
    let movesCount: Int
    let elapsedSeconds: Int
    let score: Int
    let onScoreTapped: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatTileView(
                title: "Moves",
                value: "\(movesCount)",
                systemImage: "arrow.left.arrow.right"
            )

            StatTileView(
                title: "Time",
                value: formattedDuration(elapsedSeconds),
                systemImage: "timer"
            )

            Button(action: onScoreTapped) {
                StatTileView(
                    title: "Score",
                    value: "\(score)",
                    systemImage: "star.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Score \(score). Open scoring details")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigit(minutes)):\(twoDigit(remainingSeconds))"
        }
        return "\(twoDigit(minutes)):\(twoDigit(remainingSeconds))"
    }

    private func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

struct StatTileView: View {
    let title: String
    let value: String
    let systemImage: String
    var isEmphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.98))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isEmphasized ? .white.opacity(0.16) : .white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(isEmphasized ? 0.16 : 0.09), lineWidth: 1)
        )
    }
}

struct TopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let variant: GameVariant
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let wasteFanSpacing: CGFloat
    let activeTarget: DropTarget?
    let hintedTarget: DropTarget?
    let isStockHinted: Bool
    let isWasteHinted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        Group {
            switch variant {
            case .klondike:
                KlondikeTopRowView(
                    viewModel: viewModel,
                    cardSize: cardSize,
                    columnSpacing: columnSpacing,
                    wasteFanSpacing: wasteFanSpacing,
                    activeTarget: activeTarget,
                    hintedTarget: hintedTarget,
                    isStockHinted: isStockHinted,
                    isWasteHinted: isWasteHinted,
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    drawingCardIDs: drawingCardIDs,
                    fanProgress: fanProgress,
                    dragGesture: dragGesture
                )
            case .freecell:
                FreeCellTopRowView(
                    viewModel: viewModel,
                    cardSize: cardSize,
                    columnSpacing: columnSpacing,
                    activeTarget: activeTarget,
                    hintedTarget: hintedTarget,
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    dragGesture: dragGesture
                )
            case .yukon:
                YukonTopRowView(
                    viewModel: viewModel,
                    cardSize: cardSize,
                    columnSpacing: columnSpacing,
                    activeTarget: activeTarget,
                    hintedTarget: hintedTarget,
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    dragGesture: dragGesture
                )
            case .pyramid:
                PyramidTopRowView(
                    viewModel: viewModel,
                    cardSize: cardSize,
                    columnSpacing: columnSpacing,
                    activeTarget: activeTarget,
                    hintedTarget: hintedTarget,
                    isStockHinted: isStockHinted,
                    isWasteHinted: isWasteHinted,
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    drawingCardIDs: drawingCardIDs,
                    fanProgress: fanProgress,
                    dragGesture: dragGesture
                )
            }
        }
    }
}

struct TableauRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let faceDownOffset: CGFloat
    let faceUpOffset: CGFloat
    let maxPileHeight: CGFloat
    let activeTarget: DropTarget?
    let hintedTarget: DropTarget?
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(Array(viewModel.state.tableau.indices), id: \.self) { index in
                TableauPileView(
                    viewModel: viewModel,
                    pileIndex: index,
                    cardSize: cardSize,
                    faceDownOffset: faceDownOffset,
                    faceUpOffset: faceUpOffset,
                    maxPileHeight: maxPileHeight,
                    isTargeted: activeTarget == .tableau(index),
                    isHintTargeted: hintedTarget == .tableau(index),
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintedCardIDs: hintedCardIDs,
                    hintWiggleToken: hintWiggleToken,
                    dragGesture: dragGesture
                )
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}

struct FoundationView: View {
    @Bindable var viewModel: SolitaireViewModel
    let index: Int
    let cardSize: CGSize
    let isTargeted: Bool
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let foundation = viewModel.state.foundations[index]
        let visibleDepth = min(foundation.count, 4)
        let startIndex = foundation.count - visibleDepth
        let isDragSource: Bool = {
            guard viewModel.isDragging, let selection = viewModel.selection else { return false }
            if case .foundation(let pile) = selection.source {
                return pile == index
            }
            return false
        }()
        let accessibleTopCard: Card? = foundation.last.flatMap { card in
            let isDragged = viewModel.isDragging && viewModel.isSelected(card: card)
            return isDragged || hiddenCardIDs.contains(card.id) ? nil : card
        }
        let isAccessibleTopCardSelected = accessibleTopCard.map {
            viewModel.isSelected(card: $0)
        } ?? false
        let highlightZ: Double = 1
        ZStack {
            PilePlaceholderView(cardSize: cardSize)
            if foundation.isEmpty {
                Image(systemName: "a")
                    .font(.system(size: cardSize.width * 0.22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
                    .allowsHitTesting(false)
            }
            DropHighlightView(
                cardSize: cardSize,
                isTargeted: isTargeted,
                isHintTargeted: isHintTargeted,
                hintOpacity: hintHighlightOpacity
            )
                .zIndex(highlightZ)
            ForEach(Array(foundation.enumerated().dropFirst(startIndex)), id: \.element.id) { cardIndex, card in
                let isTopCard = cardIndex == foundation.count - 1
                let isDragged = isTopCard && viewModel.isDragging && viewModel.isSelected(card: card)
                let isHidden = hiddenCardIDs.contains(card.id)
                let cardView = CardView(
                    card: card,
                    isSelected: isTopCard && viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil,
                    isAccessibilityElement: false
                )
                .opacity(isDragged || isHidden ? 0 : 1)
                .zIndex(isTopCard && isDragged ? 20 : 0)
                .allowsHitTesting(isTopCard && !isHidden)

                if isTopCard {
                    cardView
                        .gesture(dragGesture(.foundation(index)))
                        .cardFramePreference(card.id)
                } else {
                    cardView
                        .allowsHitTesting(false)
                }
            }
        }
        .onTapGesture {
            viewModel.handleFoundationTap(index: index)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isAccessibleTopCardSelected ? .isSelected : [])
        .background(
            GeometryReader { proxy in
                let boardFrame = proxy.frame(in: .named("board"))
                let hitFrame = boardFrame.expanded(
                    horizontal: DropTargetHitArea.foundationHorizontalGrace,
                    top: DropTargetHitArea.foundationTopGrace,
                    bottom: DropTargetHitArea.foundationBottomGrace
                )
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .foundation(index): DropTargetGeometry(
                                snapFrame: boardFrame,
                                hitFrame: hitFrame
                            )
                        ]
                    )
            }
        )
        .zIndex(isDragSource ? 10 : 0)
        .accessibilityLabel("Foundation \(index + 1)")
        .accessibilityValue(accessibleTopCard?.accessibilityName ?? "Empty")
    }
}

struct TableauPileView: View {
    @Bindable var viewModel: SolitaireViewModel
    let pileIndex: Int
    let cardSize: CGSize
    let faceDownOffset: CGFloat
    let faceUpOffset: CGFloat
    let maxPileHeight: CGFloat
    let isTargeted: Bool
    let isHintTargeted: Bool
    let hintHighlightOpacity: Double
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let hintedCardIDs: Set<UUID>
    let hintWiggleToken: UUID
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        if viewModel.state.tableau.indices.contains(pileIndex) {
            let isDragSource: Bool = {
                guard viewModel.isDragging, let selection = viewModel.selection else { return false }
                if case .tableau(let pile, _) = selection.source {
                    return pile == pileIndex
                }
                return false
            }()

            let pile = viewModel.state.tableau[pileIndex]
            let yOffsets = tableauYOffsets(for: pile)
            let topCardYOffset = yOffsets.last ?? 0
            let stackDropYOffset = dropYOffset(for: pile, yOffsets: yOffsets)
            let height = max(cardSize.height, cardSize.height + topCardYOffset)
            let highlightYOffset: CGFloat = {
                guard viewModel.isDragging, let selection = viewModel.selection else {
                    return stackDropYOffset
                }
                if case .tableau(let sourcePile, let sourceIndex) = selection.source,
                   sourcePile == pileIndex,
                   sourceIndex < yOffsets.count {
                    return yOffsets[sourceIndex]
                }
                return stackDropYOffset
            }()
            let highlightZ: Double = Double(pile.count) + 0.5

            ZStack(alignment: .top) {
                Color.clear
                    .frame(width: cardSize.width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.handleTableauTap(pileIndex: pileIndex, cardIndex: nil)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Tableau \(pileIndex + 1)")
                    .accessibilityValue("Empty")
                    .accessibilityHidden(!pile.isEmpty)

                PilePlaceholderView(cardSize: cardSize)
                DropHighlightView(
                    cardSize: cardSize,
                    isTargeted: isTargeted,
                    isHintTargeted: isHintTargeted,
                    hintOpacity: hintHighlightOpacity
                )
                    .offset(y: highlightYOffset)
                    .zIndex(highlightZ)

                ForEach(Array(pile.enumerated()), id: \.element.id) { index, card in
                    let isDragged = viewModel.isDragging && viewModel.isSelected(card: card)
                    let isHidden = hiddenCardIDs.contains(card.id)
                    let isSelected = viewModel.isSelected(card: card)
                    let selectableCards = Array(pile[index...])
                    let isValidRunOrigin = card.isFaceUp
                        && viewModel.canSelectTableauCards(selectableCards)
                    let isExposedFaceDownCard = viewModel.state.variant.dealsFaceDownTableauCards
                        && !card.isFaceUp
                        && index == pile.indices.last
                    let isAccessibilityElement = (isValidRunOrigin || isExposedFaceDownCard)
                        && !isDragged
                        && !isHidden
                    let multiCardNoun = viewModel.state.variant == .yukon ? "group" : "run"
                    let accessibilityHint = isExposedFaceDownCard
                        ? "Flip card"
                        : selectableCards.count > 1
                            ? "Selects a \(selectableCards.count)-card \(multiCardNoun)"
                            : "Selects this card"
                    let yOffset = yOffsets[index]
                    let cardView = CardView(
                        card: card,
                        isSelected: isSelected,
                        cardSize: cardSize,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        hintWiggleToken: hintedCardIDs.contains(card.id) ? hintWiggleToken : nil,
                        isAccessibilityElement: isAccessibilityElement
                    )
                    .opacity(isDragged || isHidden ? 0 : 1)
                    .offset(x: 0, y: yOffset)
                    .zIndex(isDragged ? 20 + Double(index) : Double(index))
                    .allowsHitTesting(!isHidden)
                    .onTapGesture {
                        viewModel.handleTableauTap(pileIndex: pileIndex, cardIndex: index)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(accessibilityHint)
                    .cardFramePreference(card.id, yOffset: yOffset)

                    cardView.gesture(dragGesture(.tableau(pile: pileIndex, index: index)))
                }
            }
            .frame(width: cardSize.width, height: height, alignment: .top)
            .background(
                GeometryReader { proxy in
                    let boardFrame = proxy.frame(in: .named("board"))
                    let snapFrame = CGRect(
                        x: boardFrame.minX,
                        y: boardFrame.minY + highlightYOffset,
                        width: cardSize.width,
                        height: cardSize.height
                    )
                    let topCardFrame = CGRect(
                        x: boardFrame.minX,
                        y: boardFrame.minY + topCardYOffset,
                        width: cardSize.width,
                        height: cardSize.height
                    )
                    let hitFrame = snapFrame
                        .union(topCardFrame)
                        .expanded(
                            horizontal: DropTargetHitArea.tableauHorizontalGrace,
                            top: DropTargetHitArea.tableauTopGrace,
                            bottom: DropTargetHitArea.tableauBottomGrace
                        )
                    Color.clear
                        .preference(
                            key: DropTargetFrameKey.self,
                            value: [
                                .tableau(pileIndex): DropTargetGeometry(
                                    snapFrame: snapFrame,
                                    hitFrame: hitFrame
                                )
                            ]
                        )
                }
            )
            .zIndex(isDragSource ? 10 : 0)
        } else {
            Color.clear
                .frame(width: cardSize.width, height: cardSize.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func tableauYOffsets(for pile: [Card]) -> [CGFloat] {
        guard !pile.isEmpty else { return [] }
        var yOffsets: [CGFloat] = []
        yOffsets.reserveCapacity(pile.count)
        var runningYOffset: CGFloat = 0

        for (index, card) in pile.enumerated() {
            yOffsets.append(runningYOffset)
            if index < pile.count - 1 {
                runningYOffset += card.isFaceUp ? faceUpOffset : faceDownOffset
            }
        }

        // Compress this pile's spread evenly when it would overflow the board.
        let maxTopOffset = maxPileHeight - cardSize.height
        if let last = yOffsets.last, last > maxTopOffset, maxTopOffset > 0 {
            let scale = maxTopOffset / last
            yOffsets = yOffsets.map { $0 * scale }
        }

        return yOffsets
    }

    private func dropYOffset(for pile: [Card], yOffsets: [CGFloat]) -> CGFloat {
        guard let lastCard = pile.last, let lastYOffset = yOffsets.last else { return 0 }
        let natural = lastYOffset + (lastCard.isFaceUp ? faceUpOffset : faceDownOffset)
        let maxTopOffset = maxPileHeight - cardSize.height
        return maxTopOffset > 0 ? min(natural, maxTopOffset) : natural
    }
}

struct PilePlaceholderView: View {
    let cardSize: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: cardSize.width * 0.12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            .frame(width: cardSize.width, height: cardSize.height)
    }
}

struct DropHighlightView: View {
    let cardSize: CGSize
    let isTargeted: Bool
    let isHintTargeted: Bool
    let hintOpacity: Double

    var body: some View {
        let cornerRadius = cardSize.width * 0.12
        let clampedHintOpacity = max(0, min(1, hintOpacity))
        let strokeColor: Color = {
            if isTargeted {
                return Color.yellow.opacity(0.85)
            }
            if isHintTargeted {
                return Color.yellow.opacity(0.85 * clampedHintOpacity)
            }
            return Color.clear
        }()

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(strokeColor, lineWidth: 2)
            .frame(width: cardSize.width, height: cardSize.height)
            .scaleEffect(1.05)
    }
}

struct TableBackground: View {
    @AppStorage(SettingsKey.tableBackgroundColor)
    private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue
    @AppStorage(SettingsKey.feltEffectEnabled) private var feltEffectEnabled = true

    var body: some View {
        let background = TableBackgroundColor(rawValue: tableBackgroundColorRawValue) ?? .defaultValue
        let baseColor = background.color
        Group {
            if feltEffectEnabled {
                GeometryReader { proxy in
                    baseColor
                        .colorEffect(ShaderLibrary.feltTexture(.float2(proxy.size)))
                }
            } else {
                baseColor
            }
        }
        .ignoresSafeArea()
    }
}

struct WinOverlay: View {
    let score: Int
    let onNewGame: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("You Won!")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Score: \(score)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Button("Play Again") {
                    onNewGame()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.0235, green: 0.4431, blue: 0.7176))
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
}

#Preview("Win Overlay") {
    WinOverlay(score: 1240) {}
}
