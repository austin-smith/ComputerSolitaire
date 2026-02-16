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
    }

    static func metrics(for boardSize: CGSize) -> Metrics {
        let boardWidth = boardSize.width
#if os(iOS)
        let isCompactBoard = boardWidth <= 430
        let isMediumBoard = boardWidth > 430 && boardWidth < 760
        let isPadLandscape = UIDevice.current.userInterfaceIdiom == .pad && boardSize.width > boardSize.height

        let horizontalPadding: CGFloat = isCompactBoard ? 12 : (isMediumBoard ? 14 : 24)
        let verticalPadding: CGFloat = isPadLandscape ? 12 : (isCompactBoard ? 16 : 24)
        let rowSpacing: CGFloat = isPadLandscape ? 16 : (isCompactBoard ? 16 : 24)
        let columnSpacing: CGFloat = isCompactBoard ? 8 : (isMediumBoard ? 10 : 18)

        let usableWidth = max(0, boardWidth - (horizontalPadding * 2))
        let fittedCardWidth = floor((usableWidth - (columnSpacing * 6)) / 7)
        let maxCardWidth: CGFloat = isPadLandscape ? 112 : (boardWidth < 760 ? 96 : 120)
        let cardWidth = max(32, min(maxCardWidth, fittedCardWidth))
        let cardSize = CGSize(width: cardWidth, height: cardWidth * 1.45)

        let baseFaceDownOffset = max(isCompactBoard ? 10 : 16, cardSize.height * (isCompactBoard ? 0.16 : 0.18))
        let baseFaceUpOffset = max(isCompactBoard ? 14 : 22, cardSize.height * (isCompactBoard ? 0.24 : 0.28))

        let faceUpOffset: CGFloat
        let faceDownOffset: CGFloat
        if isPadLandscape {
            let landscapeOffsetScale: CGFloat = 0.72
            faceUpOffset = max(22, baseFaceUpOffset * landscapeOffsetScale)
            faceDownOffset = max(14, baseFaceDownOffset * landscapeOffsetScale)
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
            wasteFanSpacing: wasteFanSpacing
        )
#else
        let horizontalPadding = min(24, max(14, boardWidth * 0.018))
        let verticalPadding = min(22, max(14, boardWidth * 0.015))
        let columnSpacing = min(18, max(10, boardWidth * 0.013))
        let rowSpacing = min(22, max(14, columnSpacing + 4))

        let usableWidth = max(0, boardWidth - (horizontalPadding * 2))
        let fittedCardWidth = floor((usableWidth - (columnSpacing * 6)) / 7)
        let maxCardWidth = min(124, max(88, boardWidth * 0.095))
        let cardWidth = max(52, min(maxCardWidth, fittedCardWidth))
        let cardSize = CGSize(width: cardWidth, height: cardWidth * 1.45)

        let faceDownOffset = max(13, cardSize.height * 0.18)
        let faceUpOffset = max(18, cardSize.height * 0.26)
        let wasteFanSpacing = cardSize.width * (boardWidth < 760 ? 0.2 : 0.25)

        return Metrics(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            rowSpacing: rowSpacing,
            columnSpacing: columnSpacing,
            cardSize: cardSize,
            tableauFaceDownOffset: faceDownOffset,
            tableauFaceUpOffset: faceUpOffset,
            wasteFanSpacing: wasteFanSpacing
        )
#endif
    }
}

enum CardTilt {
    static let angleRange: ClosedRange<Double> = -2.0...2.0
}

struct HeaderView: View {
    let movesCount: Int
    let score: Int
    let onScoreTapped: () -> Void

    var body: some View {
        HStack {
            Text("Moves \(movesCount)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Button(action: onScoreTapped) {
                Text("Score \(score)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

struct TopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let wasteFanSpacing: CGFloat
    let activeTarget: DropTarget?
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            StockView(viewModel: viewModel, cardSize: cardSize)
                .frame(width: cardSize.width, alignment: .leading)
            WasteView(
                viewModel: viewModel,
                cardSize: cardSize,
                fanSpacing: wasteFanSpacing,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                hiddenCardIDs: hiddenCardIDs,
                drawingCardIDs: drawingCardIDs,
                fanProgress: fanProgress,
                dragGesture: dragGesture
            )
            // Keep top-row columns aligned with tableau; waste fan can overflow visually
            // without changing foundation positions.
            .frame(width: cardSize.width, alignment: .leading)

            Color.clear
                .frame(width: cardSize.width, height: cardSize.height)
                .accessibilityHidden(true)

            ForEach(0..<4, id: \.self) { index in
                FoundationView(
                    viewModel: viewModel,
                    index: index,
                    cardSize: cardSize,
                    isTargeted: activeTarget == .foundation(index),
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    dragGesture: dragGesture
                )
                .frame(width: cardSize.width, alignment: .leading)
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}

struct TableauRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let columnSpacing: CGFloat
    let faceDownOffset: CGFloat
    let faceUpOffset: CGFloat
    let activeTarget: DropTarget?
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(0..<7, id: \.self) { index in
                TableauPileView(
                    viewModel: viewModel,
                    pileIndex: index,
                    cardSize: cardSize,
                    faceDownOffset: faceDownOffset,
                    faceUpOffset: faceUpOffset,
                    isTargeted: activeTarget == .tableau(index),
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    hiddenCardIDs: hiddenCardIDs,
                    dragGesture: dragGesture
                )
            }
        }
#if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }
}

struct StockView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize

    var body: some View {
        ZStack {
            PilePlaceholderView(cardSize: cardSize)
                .allowsHitTesting(false)
            if viewModel.state.stock.isEmpty {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                CardBackView(cardSize: cardSize)
            }
            Text("\(viewModel.state.stock.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .offset(x: cardSize.width * 0.28, y: cardSize.height * 0.38)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: StockFrameKey.self, value: proxy.frame(in: .named("board")))
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.handleStockTap()
        }
        .accessibilityLabel("Stock")
    }
}

struct WasteView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let fanSpacing: CGFloat
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let drawingCardIDs: Set<UUID>
    let fanProgress: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let isDragSource: Bool = {
            guard viewModel.isDragging, let selection = viewModel.selection else { return false }
            if case .waste = selection.source {
                return true
            }
            return false
        }()
        let visibleWaste = viewModel.visibleWasteCards()
        let isSelected = visibleWaste.contains(where: { viewModel.isSelected(card: $0) })
        let fanWidth = fanSpacing * CGFloat(max(0, visibleWaste.count - 1))

        ZStack(alignment: .topLeading) {
            PilePlaceholderView(cardSize: cardSize)
            ForEach(Array(visibleWaste.enumerated()), id: \.element.id) { index, card in
                let isTopCard = index == visibleWaste.count - 1
                let isDragged = isTopCard && viewModel.isDragging && viewModel.isSelected(card: card)
                let isDrawing = drawingCardIDs.contains(card.id)
                let isHidden = hiddenCardIDs.contains(card.id)
                let progress = fanProgress[card.id] ?? 1
                let xOffset = CGFloat(index) * fanSpacing * progress
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts
                )
                .opacity(isDragged || isDrawing || isHidden ? 0 : 1)
                .offset(x: xOffset, y: 0)
                .zIndex(isTopCard ? 2 : Double(index))
                .allowsHitTesting(isTopCard && !isDrawing && !isHidden)
                .cardFramePreference(card.id, xOffset: xOffset)

                if isTopCard {
                    cardView.gesture(dragGesture(.waste))
                } else {
                    cardView
                }
            }
        }
        .frame(width: cardSize.width + fanWidth, height: cardSize.height, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: WasteFrameKey.self, value: proxy.frame(in: .named("board")))
            }
        )
        .onTapGesture {
            viewModel.handleWasteTap()
        }
        .zIndex(isDragSource || isSelected ? 10 : 0)
        .accessibilityLabel("Waste")
    }
}

struct FoundationView: View {
    @Bindable var viewModel: SolitaireViewModel
    let index: Int
    let cardSize: CGSize
    let isTargeted: Bool
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
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
        let highlightZ: Double = 1
        ZStack {
            PilePlaceholderView(cardSize: cardSize)
            DropHighlightView(cardSize: cardSize, isTargeted: isTargeted)
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
                    cardTilts: $cardTilts
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
    }
}

struct TableauPileView: View {
    @Bindable var viewModel: SolitaireViewModel
    let pileIndex: Int
    let cardSize: CGSize
    let faceDownOffset: CGFloat
    let faceUpOffset: CGFloat
    let isTargeted: Bool
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hiddenCardIDs: Set<UUID>
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
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

            PilePlaceholderView(cardSize: cardSize)
            DropHighlightView(cardSize: cardSize, isTargeted: isTargeted)
                .offset(y: highlightYOffset)
                .zIndex(highlightZ)

            ForEach(Array(pile.enumerated()), id: \.element.id) { index, card in
                let isDragged = viewModel.isDragging && viewModel.isSelected(card: card)
                let isHidden = hiddenCardIDs.contains(card.id)
                let yOffset = yOffsets[index]
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts
                )
                .opacity(isDragged || isHidden ? 0 : 1)
                .offset(x: 0, y: yOffset)
                .zIndex(isDragged ? 20 + Double(index) : Double(index))
                .allowsHitTesting(!isHidden)
                .onTapGesture {
                    viewModel.handleTableauTap(pileIndex: pileIndex, cardIndex: index)
                }
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
        .accessibilityLabel("Tableau \(pileIndex + 1)")
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

        return yOffsets
    }

    private func dropYOffset(for pile: [Card], yOffsets: [CGFloat]) -> CGFloat {
        guard let lastCard = pile.last, let lastYOffset = yOffsets.last else { return 0 }
        return lastYOffset + (lastCard.isFaceUp ? faceUpOffset : faceDownOffset)
    }
}

struct CardView: View {
    let card: Card
    let isSelected: Bool
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let flipOnAppear: Bool
    let flipDelay: Double
    @State private var flipRotation: Double
    @State private var tiltAngle: Double = 0

    init(
        card: Card,
        isSelected: Bool,
        cardSize: CGSize,
        isCardTiltEnabled: Bool,
        cardTilts: Binding<[UUID: Double]>,
        flipOnAppear: Bool = false,
        flipDelay: Double = 0
    ) {
        self.card = card
        self.isSelected = isSelected
        self.cardSize = cardSize
        self.isCardTiltEnabled = isCardTiltEnabled
        self._cardTilts = cardTilts
        self.flipOnAppear = flipOnAppear
        self.flipDelay = flipDelay
        let startFaceDown = flipOnAppear && card.isFaceUp
        _flipRotation = State(initialValue: startFaceDown ? 180 : (card.isFaceUp ? 0 : 180))
    }

    private var targetTiltAngle: Double {
        if !isCardTiltEnabled { return 0 }
        if let existing = cardTilts[card.id] { return existing }
        let newTilt = Double.random(in: CardTilt.angleRange)
        DispatchQueue.main.async {
            cardTilts[card.id] = newTilt
        }
        return newTilt
    }

    var body: some View {
        let cornerRadius = cardSize.width * 0.12
        let borderColor = isSelected ? Color.yellow.opacity(0.9) : Color.black.opacity(0.2)
        let borderWidth: CGFloat = isSelected ? 3 : 1
        let shadowColor = Color.black.opacity(isSelected ? 0.35 : 0.2)
        let shadowRadius: CGFloat = isSelected ? 8 : 4
        let shadowYOffset: CGFloat = isSelected ? 6 : 2
        let frontAngle = flipRotation
        let backAngle = flipRotation - 180
        let frontOpacity = flipRotation < 90 ? 1.0 : 0.0
        let backOpacity = flipRotation < 90 ? 0.0 : 1.0

        ZStack {
            cardFront(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
            .opacity(frontOpacity)
            .rotation3DEffect(.degrees(frontAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.7)

            cardBack(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
            .opacity(backOpacity)
            .rotation3DEffect(.degrees(backAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .rotationEffect(.degrees(tiltAngle))
        .scaleEffect(isSelected ? 1.03 : 1)
        .onChange(of: card.isFaceUp) { _, newValue in
            withAnimation(.easeInOut(duration: 0.32)) {
                flipRotation = newValue ? 0 : 180
            }
        }
        .onAppear {
            if flipOnAppear, card.isFaceUp, flipRotation != 0 {
                withAnimation(.easeInOut(duration: 0.22).delay(flipDelay)) {
                    flipRotation = 0
                }
            }
            withAnimation(.easeOut(duration: 0.2)) {
                tiltAngle = targetTiltAngle
            }
        }
    }

    private func cardFront(
        cornerRadius: CGFloat,
        borderColor: Color,
        borderWidth: CGFloat,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) -> some View {
        let parchment = Color(red: 0.98, green: 0.96, blue: 0.91)
        let inkColor = card.suit.isRed ? Color(red: 0.72, green: 0.16, blue: 0.18) : Color(red: 0.12, green: 0.12, blue: 0.12)
        let ornamentColor = Color(red: 0.66, green: 0.58, blue: 0.48)
        let cornerMark = VStack(alignment: .leading, spacing: 2) {
            Text(card.rank.label)
                .font(.system(size: cardSize.width * 0.28, weight: .bold, design: .serif))
            Image(systemName: card.suit.symbolName)
                .font(.system(size: cardSize.width * 0.2, weight: .semibold))
        }

        return ZStack {
            cardBase(
                cornerRadius: cornerRadius,
                fill: parchment,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.clear],
                            startPoint: UnitPoint.topLeading,
                            endPoint: UnitPoint.bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * 0.92, style: .continuous)
                    .strokeBorder(ornamentColor.opacity(0.6), lineWidth: 1)
                    .padding(cardSize.width * 0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * 0.78, style: .continuous)
                    .strokeBorder(
                        ornamentColor.opacity(0.45),
                        style: StrokeStyle(lineWidth: 0.6, dash: [4, 3])
                    )
                    .padding(cardSize.width * 0.1)
            )

            cornerMark
                .foregroundStyle(inkColor)
                .padding(cardSize.width * 0.1)
                .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.topLeading)

            cornerMark
                .foregroundStyle(inkColor)
                .rotationEffect(.degrees(180))
                .padding(cardSize.width * 0.1)
                .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.bottomTrailing)

            Image(systemName: card.suit.symbolName)
                .font(.system(size: cardSize.width * 0.52, weight: .regular))
                .foregroundStyle(inkColor.opacity(0.12))
                .rotationEffect(.degrees(8))
                .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.center)
        }
    }

    private func cardBack(
        cornerRadius: CGFloat,
        borderColor: Color,
        borderWidth: CGFloat,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) -> some View {
        let lacquer = Color(red: 0.18, green: 0.26, blue: 0.52)
        let trim = Color(red: 0.78, green: 0.85, blue: 0.95)

        return ZStack {
            cardBase(
                cornerRadius: cornerRadius,
                fill: lacquer,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * 0.92, style: .continuous)
                    .strokeBorder(trim.opacity(0.55), lineWidth: 1)
                    .padding(cardSize.width * 0.08)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * 0.8, style: .continuous)
                    .strokeBorder(trim.opacity(0.35), style: StrokeStyle(lineWidth: 0.6, dash: [5, 3]))
                    .padding(cardSize.width * 0.12)
            )

            CardBackPattern()
                .padding(cardSize.width * 0.18)
        }
    }

    private func cardBase(
        cornerRadius: CGFloat,
        fill: Color,
        borderColor: Color,
        borderWidth: CGFloat,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
    }
}

struct CardBackPattern: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                Path { path in
                    let step: CGFloat = 10
                    var x: CGFloat = 0
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                Path { path in
                    let step: CGFloat = 10
                    var y: CGFloat = 0
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

struct CardBackView: View {
    let cardSize: CGSize

    var body: some View {
        let cornerRadius = cardSize.width * 0.12
        let lacquer = Color(red: 0.18, green: 0.26, blue: 0.52)
        let trim = Color(red: 0.78, green: 0.85, blue: 0.95)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(lacquer)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(trim.opacity(0.5), lineWidth: 1)
                        .padding(cardSize.width * 0.06)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(trim.opacity(0.25), style: StrokeStyle(lineWidth: 0.6, dash: [5, 3]))
                        .padding(cardSize.width * 0.1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

            CardBackPattern()
                .padding(cardSize.width * 0.18)
        }
        .frame(width: cardSize.width, height: cardSize.height)
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

    var body: some View {
        let cornerRadius = cardSize.width * 0.12

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(isTargeted ? Color.yellow.opacity(0.85) : Color.clear, lineWidth: 2)
            .frame(width: cardSize.width, height: cardSize.height)
            .scaleEffect(1.05)
    }
}

struct TableBackground: View {
    @AppStorage(SettingsKey.tableBackgroundColor) private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue
    @AppStorage(SettingsKey.feltEffectEnabled) private var feltEffectEnabled = true

    var body: some View {
        let baseColor = (TableBackgroundColor(rawValue: tableBackgroundColorRawValue) ?? TableBackgroundColor.defaultValue).color
        ZStack {
            baseColor

            if feltEffectEnabled {
                // Felt fiber texture
                FeltTextureOverlay()

                // Vignette: darken edges for a real table look
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(0.35)
                    ]),
                    center: .center,
                    startRadius: 100,
                    endRadius: 900
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Procedural felt fiber noise drawn via Canvas.
private struct FeltTextureOverlay: View {
    var body: some View {
        Canvas { context, size in
            // Deterministic seed-based RNG for consistent pattern
            var rng = FeltRNG(seed: 42)
            let count = Int(size.width * size.height * 0.06)
            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let brightness = rng.next()
                let opacity = 0.03 + Double(brightness) * 0.06
                let length = 1.5 + CGFloat(rng.next()) * 3.0
                let angle = Angle.degrees(Double(rng.next()) * 360)

                var path = Path()
                let dx = cos(angle.radians) * length
                let dy = sin(angle.radians) * length
                path.move(to: CGPoint(x: x - dx, y: y - dy))
                path.addLine(to: CGPoint(x: x + dx, y: y + dy))

                let isLight = brightness > 0.5
                let color = isLight
                    ? Color.white.opacity(opacity)
                    : Color.black.opacity(opacity)
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
    }
}

/// Simple splitmix-style RNG for deterministic felt pattern.
private struct FeltRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Returns a value in 0..<1
    mutating func next() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z = z ^ (z >> 31)
        return Double(z &>> 11) / Double(1 << 53)
    }
}

struct WinOverlay: View {
    let onNewGame: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("You Win")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Every card is home.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Button("Play Again") {
                    onNewGame()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.76, blue: 0.2))
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
