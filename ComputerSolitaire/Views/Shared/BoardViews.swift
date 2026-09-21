import SwiftUI

struct HeaderView: View {
    /// Used only for the first layout pass; ContentView replaces it with the
    /// rendered height so future header changes cannot stale the board budget.
    static let estimatedHeight: CGFloat = 82

    let gameTitle: String
    /// The mode qualifier shown dimmed after the title ("3-card"); nil for
    /// single-mode games.
    let gameQualifier: String?
    let movesCount: Int
    let elapsedSeconds: Int
    let score: Int
    /// Golf titles its score tile with the hole in play ("Hole 3/9") and adds
    /// a running match-total tile; nil for every other game.
    var golfHoleLabel: String?
    var golfMatchTotal: Int?
    let onGameTitleTapped: () -> Void
    let onScoreTapped: () -> Void

    @AppStorage(SettingsKey.showGameStats) private var isGameStatsVisible = true

    // The title gets its own row so the stat strip keeps the full board
    // width and stays balanced over the board; sharing a row would push the
    // strip off the board's centerline.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            gameTitleButton
                .padding(.leading, 4)
            if isGameStatsVisible {
                HStack(spacing: 10) {
                    statTiles
                }
                .headerContainer()
            }
        }
    }

    private var gameTitleButton: some View {
        Button(action: onGameTitleTapped) {
            GameTitleView(title: gameTitle, qualifier: gameQualifier)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Game: \(accessibilityGameName). Switch game mode")
    }

    private var accessibilityGameName: String {
        guard let gameQualifier else { return gameTitle }
        return "\(gameTitle), \(gameQualifier)"
    }

    @ViewBuilder
    private var statTiles: some View {
        StatTileView(
            title: "Moves",
            value: "\(movesCount)"
        )

        StatTileView(
            title: "Time",
            value: formattedDuration(elapsedSeconds)
        )

        Button(action: onScoreTapped) {
            StatTileView(
                title: golfHoleLabel ?? "Score",
                value: "\(score)"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Score \(score). Open scoring details")

        if let golfMatchTotal {
            StatTileView(
                title: "Match",
                value: "\(golfMatchTotal)"
            )
        }
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

private extension View {
    /// The header strip's outer chrome: translucent dark rounded container.
    func headerContainer() -> some View {
        self
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
}

/// The current game's name set directly on the felt, like a card table's
/// engraved branding. The mode qualifier renders dimmed — it modifies the
/// name, it isn't part of it. Chevron signals the tap-to-switch affordance.
struct GameTitleView: View {
    let title: String
    let qualifier: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(styledTitle)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var styledTitle: AttributedString {
        var styled = AttributedString(title.uppercased())
        if let qualifier {
            var suffix = AttributedString(" · \(qualifier.uppercased())")
            suffix.foregroundColor = .white.opacity(0.5)
            styled += suffix
        }
        return styled
    }
}

/// One stat in the header strip: a quiet uppercase label over its value,
/// echoing the game title's felt-set typography. The strip's container is
/// the only chrome — tiles are bare type.
struct StatTileView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.98))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TopRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let board: TopRowSnapshot
    let selection: SelectionSnapshot
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
            switch board.variant {
            case .klondike:
                KlondikeTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
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
                    session: session,
                    board: board,
                    selection: selection,
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
                    session: session,
                    board: board,
                    selection: selection,
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
            case .spider:
                SpiderTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
                    cardSize: cardSize,
                    columnSpacing: columnSpacing,
                    isStockHinted: isStockHinted,
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintWiggleToken: hintWiggleToken
                )
            case .scorpion:
                ScorpionTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
                    cardSize: cardSize,
                    columnSpacing: columnSpacing,
                    isStockHinted: isStockHinted,
                    hintHighlightOpacity: hintHighlightOpacity,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    hintWiggleToken: hintWiggleToken
                )
            case .pyramid:
                PyramidTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
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
            case .tripeaks:
                TriPeaksTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
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
            case .golf:
                GolfTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
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
            case .fortyThieves:
                FortyThievesTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
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
            case .canfield:
                CanfieldTopRowView(
                    session: session,
                    board: board,
                    selection: selection,
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
            }
        }
    }
}

/// Prunes the whole top row when nothing it renders changed; see
/// TableauPileView's Equatable note for the exclusion contract.
///
/// Tilt writes deliberately have no place here: `cardTilts` reaches each
/// CardView as a binding it reads in its own body, so a tilt write (the
/// waste-return reroll included) invalidates the affected CardView directly —
/// pruning any ancestor, this row included, cannot stale it. That direct
/// dependency is the contract a CardView refactor must preserve.
extension TopRowView: Equatable {
    nonisolated static func == (lhs: TopRowView, rhs: TopRowView) -> Bool {
        lhs.session === rhs.session
            && lhs.board == rhs.board
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.columnSpacing == rhs.columnSpacing
            && lhs.wasteFanSpacing == rhs.wasteFanSpacing
            && lhs.activeTarget == rhs.activeTarget
            && lhs.hintedTarget == rhs.hintedTarget
            && lhs.isStockHinted == rhs.isStockHinted
            && lhs.isWasteHinted == rhs.isWasteHinted
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
            && lhs.drawingCardIDs == rhs.drawingCardIDs
            && lhs.fanProgress == rhs.fanProgress
    }
}

struct TableauRowView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    let tableau: [[Card]]
    let variant: GameVariant
    let selection: SelectionSnapshot
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
        BoardRow(spacing: columnSpacing) {
            ForEach(Array(tableau.indices), id: \.self) { index in
                TableauPileView(
                    session: session,
                    pile: tableau[index],
                    pileIndex: index,
                    variant: variant,
                    selection: selection,
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

/// Prunes the whole tableau subtree between drop-target crossings; see
/// TableauPileView's Equatable note for the exclusion contract.
extension TableauRowView: Equatable {
    nonisolated static func == (lhs: TableauRowView, rhs: TableauRowView) -> Bool {
        lhs.session === rhs.session
            && lhs.tableau == rhs.tableau
            && lhs.variant == rhs.variant
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.columnSpacing == rhs.columnSpacing
            && lhs.faceDownOffset == rhs.faceDownOffset
            && lhs.faceUpOffset == rhs.faceUpOffset
            && lhs.maxPileHeight == rhs.maxPileHeight
            && lhs.activeTarget == rhs.activeTarget
            && lhs.hintedTarget == rhs.hintedTarget
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}

struct FoundationView: View {
    /// Event wiring only; never read in body.
    let session: SolitaireViewModel
    /// nil when a variant switch left this index without a pile — the view
    /// stays mounted rendering nothing, exactly like the old in-body guard,
    /// so the row's layout holds through the transient.
    let pile: [Card]?
    let index: Int
    let placeholder: FoundationPlaceholder
    let selection: SelectionSnapshot
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
        if let foundation = pile {
            let visibleDepth = min(foundation.count, 4)
            let startIndex = foundation.count - visibleDepth
            let isDragSource: Bool = {
                if case .foundation(let sourcePile) = selection.dragSource {
                    return sourcePile == index
                }
                return false
            }()
            let accessibleTopCard: Card? = foundation.last.flatMap { card in
                let isDragged = selection.isDragging && selection.isSelected(card)
                return isDragged || hiddenCardIDs.contains(card.id) ? nil : card
            }
            let isAccessibleTopCardSelected = accessibleTopCard.map {
                selection.isSelected($0)
            } ?? false
            let highlightZ: Double = 1
            ZStack {
                PilePlaceholderView(cardSize: cardSize)
                if foundation.isEmpty {
                    switch placeholder {
                    case .ace:
                        Image(systemName: "a")
                            .font(.system(size: cardSize.width * 0.22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.28))
                            .allowsHitTesting(false)
                    case .baseRank(let rank):
                        // Canfield foundations start at the dealt base rank.
                        Text(rank.label)
                            .font(.system(size: cardSize.width * 0.22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.28))
                            .allowsHitTesting(false)
                    case .blank:
                        EmptyView()
                    }
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
                    let isDragged = isTopCard && selection.isDragging && selection.isSelected(card)
                    let isHidden = hiddenCardIDs.contains(card.id)
                    let cardView = CardView(
                        card: card,
                        isSelected: isTopCard && selection.isSelected(card),
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
                session.handleFoundationTap(index: index)
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
                            key: BoardFrameKey.self,
                            value: BoardFramePreferences(dropTargets: [
                                .foundation(index): DropTargetGeometry(
                                    snapFrame: boardFrame,
                                    hitFrame: hitFrame
                                )
                            ])
                        )
                }
            )
            .zIndex(isDragSource ? 10 : 0)
            .accessibilityLabel("Foundation \(index + 1)")
            .accessibilityValue(accessibleTopCard?.accessibilityName ?? "Empty")
        }
    }
}

/// See TableauPileView's Equatable note for the exclusion contract.
extension FoundationView: Equatable {
    nonisolated static func == (lhs: FoundationView, rhs: FoundationView) -> Bool {
        lhs.session === rhs.session
            && lhs.pile == rhs.pile
            && lhs.index == rhs.index
            && lhs.placeholder == rhs.placeholder
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.isTargeted == rhs.isTargeted
            && lhs.isHintTargeted == rhs.isHintTargeted
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
    }
}

struct TableauPileView: View {
    /// Event wiring only (taps route through it); never read in body —
    /// reading the observable session while rendering would re-couple this
    /// pile to whole-board invalidation.
    let session: SolitaireViewModel
    let pile: [Card]
    let pileIndex: Int
    let variant: GameVariant
    let selection: SelectionSnapshot
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
        let isDragSource: Bool = {
            if case .tableau(let sourcePile, _) = selection.dragSource {
                return sourcePile == pileIndex
            }
            return false
        }()

        let yOffsets = tableauYOffsets(for: pile)
        let topCardYOffset = yOffsets.last ?? 0
        let stackDropYOffset = dropYOffset(for: pile, yOffsets: yOffsets)
        let height = max(cardSize.height, cardSize.height + topCardYOffset)
        let highlightYOffset: CGFloat = {
            if case .tableau(let sourcePile, let sourceIndex) = selection.dragSource,
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
                    session.handleTableauTap(pileIndex: pileIndex, cardIndex: nil)
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
                let isDragged = selection.isDragging && selection.isSelected(card)
                let isHidden = hiddenCardIDs.contains(card.id)
                let isSelected = selection.isSelected(card)
                let selectableCards = Array(pile[index...])
                let isValidRunOrigin = card.isFaceUp
                    && GameRules.canSelectTableauCards(selectableCards, within: pile, variant: variant)
                let isExposedFaceDownCard = variant.dealsFaceDownTableauCards
                    && !card.isFaceUp
                    && index == pile.indices.last
                let isAccessibilityElement = (isValidRunOrigin || isExposedFaceDownCard)
                    && !isDragged
                    && !isHidden
                // Yukon and Scorpion groups need not be ordered; every
                // other multi-card pickup is a run.
                let isGroupMoveVariant = variant == .yukon || variant == .scorpion
                let multiCardNoun = isGroupMoveVariant ? "group" : "run"
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
                    session.handleTableauTap(pileIndex: pileIndex, cardIndex: index)
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
                        key: BoardFrameKey.self,
                        value: BoardFramePreferences(dropTargets: [
                            .tableau(pileIndex): DropTargetGeometry(
                                snapFrame: snapFrame,
                                hitFrame: hitFrame
                            )
                        ])
                    )
            }
        )
        .zIndex(isDragSource ? 10 : 0)
    }

    private func tableauYOffsets(for pile: [Card]) -> [CGFloat] {
        Layout.tableauOffsets(for: pile, cardHeight: cardSize.height,
                              faceDownOffset: faceDownOffset, faceUpOffset: faceUpOffset,
                              maxPileHeight: maxPileHeight)
    }

    private func dropYOffset(for pile: [Card], yOffsets: [CGFloat]) -> CGFloat {
        guard let lastCard = pile.last, let lastYOffset = yOffsets.last else { return 0 }
        let natural = lastYOffset + (lastCard.isFaceUp ? faceUpOffset : faceDownOffset)
        let maxTopOffset = maxPileHeight - cardSize.height
        return maxTopOffset > 0 ? min(natural, maxTopOffset) : natural
    }
}

/// Covers every rendered input so an unrelated move prunes this pile. The
/// session participates by identity only (event wiring); the tilt binding and
/// gesture closure are excluded — both act purely through identity-stable
/// storage, the contract CardView's Equatable documents. Card-level tilt
/// changes always accompany a pile-content change here (only the waste
/// rerolls a tilt in place), so no per-card tilt capture is needed.
extension TableauPileView: Equatable {
    nonisolated static func == (lhs: TableauPileView, rhs: TableauPileView) -> Bool {
        lhs.session === rhs.session
            && lhs.pile == rhs.pile
            && lhs.pileIndex == rhs.pileIndex
            && lhs.variant == rhs.variant
            && lhs.selection == rhs.selection
            && lhs.cardSize == rhs.cardSize
            && lhs.faceDownOffset == rhs.faceDownOffset
            && lhs.faceUpOffset == rhs.faceUpOffset
            && lhs.maxPileHeight == rhs.maxPileHeight
            && lhs.isTargeted == rhs.isTargeted
            && lhs.isHintTargeted == rhs.isHintTargeted
            && lhs.hintHighlightOpacity == rhs.hintHighlightOpacity
            && lhs.isCardTiltEnabled == rhs.isCardTiltEnabled
            && lhs.hiddenCardIDs == rhs.hiddenCardIDs
            && lhs.hintedCardIDs == rhs.hintedCardIDs
            && lhs.hintWiggleToken == rhs.hintWiggleToken
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
        // Modal to VoiceOver: the board underneath is won and inert; the only
        // action is dealing again.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("Win Overlay") {
    WinOverlay(score: 1240) {}
}
