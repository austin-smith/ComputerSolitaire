import SwiftUI

private enum DropTarget: Hashable {
    case foundation(Int)
    case tableau(Int)
}

private enum DragOrigin: Hashable {
    case waste
    case foundation(Int)
    case tableau(pile: Int, index: Int)
}

private struct DropTargetFrameKey: PreferenceKey {
    static var defaultValue: [DropTarget: CGRect] = [:]

    static func reduce(value: inout [DropTarget: CGRect], nextValue: () -> [DropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CardFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CardFramePreference: ViewModifier {
    let cardID: UUID
    let xOffset: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("board"))
                let adjustedFrame = CGRect(
                    x: frame.minX + xOffset,
                    y: frame.minY + yOffset,
                    width: frame.width,
                    height: frame.height
                )
                Color.clear
                    .preference(key: CardFrameKey.self, value: [cardID: adjustedFrame])
            }
        )
    }
}

private extension View {
    func cardFramePreference(_ cardID: UUID, xOffset: CGFloat = 0, yOffset: CGFloat = 0) -> some View {
        modifier(CardFramePreference(cardID: cardID, xOffset: xOffset, yOffset: yOffset))
    }
}

struct ContentView: View {
    @State private var viewModel = SolitaireViewModel()
    @State private var dropFrames: [DropTarget: CGRect] = [:]
    @State private var activeTarget: DropTarget?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragReturnOffset: CGSize = .zero
    @State private var isReturningDrag = false
    @State private var returningCards: [Card] = []
    @State private var isDroppingCards = false
    @State private var droppingSelection: Selection?
    @State private var dropAnimationOffset: CGSize = .zero
    @State private var pendingDropDestination: Destination?
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var cardTilts: [UUID: Double] = [:]
    @State private var overlayTilt: Double = 0
    @State private var isShowingSettings = false

    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue

    private var drawMode: DrawMode {
        DrawMode(rawValue: drawModeRawValue) ?? .three
    }

    var body: some View {
        GeometryReader { geometry in
            let cardSize = Layout.cardSize(for: geometry.size.width)
            let tableauOffset = Layout.tableauOffset(for: cardSize.height)

            ZStack {
                TableBackground()

                VStack(spacing: 24) {
                    HeaderView(movesCount: viewModel.movesCount)
                    TopRowView(
                        viewModel: viewModel,
                        cardSize: cardSize,
                        activeTarget: activeTarget,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        dragGesture: dragGesture(for:)
                    )
                    TableauRowView(
                        viewModel: viewModel,
                        cardSize: cardSize,
                        tableauOffset: tableauOffset,
                        activeTarget: activeTarget,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        dragGesture: dragGesture(for:)
                    )
                    Spacer(minLength: 0)
                }
                .padding(24)

                if viewModel.isWin {
                    WinOverlay {
                        viewModel.newGame(drawMode: drawMode)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "board")
            .onPreferenceChange(DropTargetFrameKey.self) { frames in
                dropFrames = frames
            }
            .onPreferenceChange(CardFrameKey.self) { frames in
                cardFrames = frames
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.state)
            .animation(.easeInOut(duration: 0.12), value: activeTarget)
            .overlay {
                GeometryReader { _ in
                    DragOverlayView(
                        viewModel: viewModel,
                        cardFrames: cardFrames,
                        cardTilts: cardTilts,
                        dragTranslation: dragTranslation,
                        dragReturnOffset: dragReturnOffset,
                        isReturningDrag: isReturningDrag,
                        returningCards: returningCards,
                        isDroppingCards: isDroppingCards,
                        droppingCards: droppingSelection?.cards ?? [],
                        dropAnimationOffset: dropAnimationOffset,
                        overlayTilt: overlayTilt
                    )
                }
                .accessibilityHidden(true)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("New Game") {
                    viewModel.newGame(drawMode: drawMode)
                }
                Button("Undo") {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo)
            }
            ToolbarItem {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            isShowingSettings = true
        }
        .onChange(of: drawModeRawValue) { (_, newValue: Int) in
            let mode = DrawMode(rawValue: newValue) ?? .three
            viewModel.updateDrawMode(mode)
        }
        .onAppear {
            viewModel.newGame(drawMode: drawMode)
        }
    }

    private func dragGesture(for origin: DragOrigin) -> AnyGesture<DragGesture.Value> {
        let gesture = DragGesture(minimumDistance: 2, coordinateSpace: .named("board"))
            .onChanged { value in
                if !viewModel.isDragging {
                    let started = startDrag(from: origin)
                    if !started { return }
                }
                dragTranslation = value.translation
                activeTarget = dropTarget(at: value.location)
            }
            .onEnded { _ in
                finishDrag()
            }
        return AnyGesture(gesture)
    }

    private func startDrag(from origin: DragOrigin) -> Bool {
        dragTranslation = .zero
        dragReturnOffset = .zero
        isReturningDrag = false
        let started: Bool
        switch origin {
        case .waste:
            started = viewModel.startDragFromWaste()
        case .foundation(let index):
            started = viewModel.startDragFromFoundation(index: index)
        case .tableau(let pile, let index):
            started = viewModel.startDragFromTableau(pileIndex: pile, cardIndex: index)
        }

        if started, let firstCard = viewModel.selection?.cards.first {
            // Start with the card's current tilt, then animate to straight
            overlayTilt = cardTilts[firstCard.id] ?? 0
            withAnimation(.easeOut(duration: 0.15)) {
                overlayTilt = 0
            }
        }
        return started
    }

    private func finishDrag() {
        guard viewModel.isDragging else {
            dragTranslation = .zero
            activeTarget = nil
            return
        }

        let target = activeTarget
        activeTarget = nil
        if let target {
            let dest = destination(for: target)
            if viewModel.canDrop(to: dest) {
                beginDropAnimation(to: target, destination: dest)
            } else {
                beginReturnAnimation()
            }
        } else {
            beginReturnAnimation()
        }
    }

    private func beginDropAnimation(to target: DropTarget, destination dest: Destination) {
        guard let selection = viewModel.selection,
              let firstCard = selection.cards.first,
              let cardFrame = cardFrames[firstCard.id],
              let targetFrame = dropFrames[target] else {
            viewModel.handleDrop(to: dest)
            dragTranslation = .zero
            return
        }

        // Calculate offset from current dragged position to destination
        let currentX = cardFrame.midX + dragTranslation.width
        let currentY = cardFrame.midY + dragTranslation.height
        let targetX = targetFrame.midX
        let targetY = targetFrame.midY

        droppingSelection = selection
        pendingDropDestination = dest
        isDroppingCards = true
        dropAnimationOffset = .zero
        // Keep viewModel.isDragging true to hide original card during animation

        let offsetToTarget = CGSize(
            width: targetX - currentX,
            height: targetY - currentY
        )

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            dropAnimationOffset = offsetToTarget
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // Clear old tilts so cards get fresh tilts at new position
            if let cards = droppingSelection?.cards {
                for card in cards {
                    cardTilts.removeValue(forKey: card.id)
                }
            }

            // Update game state without animation to prevent double-animation
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if let dest = pendingDropDestination {
                    viewModel.handleDrop(to: dest)
                }
                dragTranslation = .zero
                dropAnimationOffset = .zero
                isDroppingCards = false
                droppingSelection = nil
                pendingDropDestination = nil
            }
        }
    }

    private func beginReturnAnimation() {
        guard !isReturningDrag else { return }
        let currentTranslation = dragTranslation
        returningCards = viewModel.selection?.cards ?? []
        let originalTilt = returningCards.first.flatMap { cardTilts[$0.id] } ?? 0
        // Keep viewModel.isDragging true to hide original card during animation
        isReturningDrag = true
        dragReturnOffset = .zero
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            dragReturnOffset = CGSize(width: -currentTranslation.width, height: -currentTranslation.height)
            overlayTilt = originalTilt
        }
        let returnDuration = 0.32
        DispatchQueue.main.asyncAfter(deadline: .now() + returnDuration) {
            viewModel.cancelDrag()
            dragTranslation = .zero
            dragReturnOffset = .zero
            isReturningDrag = false
            returningCards = []
        }
    }

    private func resetReturnState() {
        dragReturnOffset = .zero
        isReturningDrag = false
    }


    private func destination(for target: DropTarget) -> Destination {
        switch target {
        case .foundation(let index):
            return .foundation(index)
        case .tableau(let index):
            return .tableau(index)
        }
    }

    private func dropTarget(at location: CGPoint) -> DropTarget? {
        if let index = (0..<4).first(where: { dropFrames[.foundation($0)]?.contains(location) == true }) {
            return .foundation(index)
        }
        if let index = (0..<7).first(where: { dropFrames[.tableau($0)]?.contains(location) == true }) {
            return .tableau(index)
        }
        return nil
    }
}

private enum Layout {
    static let tableauSpacing: CGFloat = 18

    static func cardSize(for width: CGFloat) -> CGSize {
        let availableWidth = width - 48
        let totalSpacing = tableauSpacing * 6
        let cardWidth = min(96, max(64, (availableWidth - totalSpacing) / 7))
        return CGSize(width: cardWidth, height: cardWidth * 1.45)
    }

    static func tableauOffset(for cardHeight: CGFloat) -> CGFloat {
        max(22, cardHeight * 0.28)
    }
}

private enum CardTilt {
    static let angleRange: ClosedRange<Double> = -2.0...2.0
}


private struct DragOverlayView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardFrames: [UUID: CGRect]
    let cardTilts: [UUID: Double]
    let dragTranslation: CGSize
    let dragReturnOffset: CGSize
    let isReturningDrag: Bool
    let returningCards: [Card]
    let isDroppingCards: Bool
    let droppingCards: [Card]
    let dropAnimationOffset: CGSize
    let overlayTilt: Double

    var body: some View {
        Group {
            if isDroppingCards {
                dragCards(droppingCards, additionalOffset: dropAnimationOffset)
            } else if isReturningDrag {
                dragCards(returningCards, additionalOffset: dragReturnOffset)
            } else if viewModel.isDragging, let selection = viewModel.selection {
                dragCards(selection.cards, additionalOffset: .zero)
            }
        }
        .allowsHitTesting(false)
        .zIndex(100)
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private func dragCards(_ cards: [Card], additionalOffset: CGSize) -> some View {
        if cards.isEmpty {
            EmptyView()
        } else {
            ForEach(cards, id: \.id) { card in
                if let frame = cardFrames[card.id] {
                    CardView(
                        card: card,
                        isSelected: true,
                        cardSize: frame.size,
                        isCardTiltEnabled: false,
                        cardTilts: .constant([:])
                    )
                    .rotationEffect(.degrees(overlayTilt))
                    .position(x: frame.midX, y: frame.midY)
                    .offset(
                        x: dragTranslation.width + additionalOffset.width,
                        y: dragTranslation.height + additionalOffset.height
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)
                }
            }
        }
    }
}

private struct HeaderView: View {
    let movesCount: Int

    var body: some View {
        HStack {
            Text("Moves \(movesCount)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
        }
    }
}

private struct TopRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let activeTarget: DropTarget?
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(spacing: 20) {
            StockView(viewModel: viewModel, cardSize: cardSize)
            WasteView(
                viewModel: viewModel,
                cardSize: cardSize,
                isCardTiltEnabled: isCardTiltEnabled,
                cardTilts: $cardTilts,
                dragGesture: dragGesture
            )
            Spacer()
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    FoundationView(
                        viewModel: viewModel,
                        index: index,
                        cardSize: cardSize,
                        isTargeted: activeTarget == .foundation(index),
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        dragGesture: dragGesture
                    )
                }
            }
        }
    }
}

private struct TableauRowView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let tableauOffset: CGFloat
    let activeTarget: DropTarget?
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: Layout.tableauSpacing) {
            ForEach(0..<7, id: \.self) { index in
                TableauPileView(
                    viewModel: viewModel,
                    pileIndex: index,
                    cardSize: cardSize,
                    offset: tableauOffset,
                    isTargeted: activeTarget == .tableau(index),
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts,
                    dragGesture: dragGesture
                )
            }
        }
    }
}

private struct StockView: View {
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
        .onTapGesture {
            viewModel.handleStockTap()
        }
        .accessibilityLabel("Stock")
    }
}

private struct WasteView: View {
    @Bindable var viewModel: SolitaireViewModel
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
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
        let fanSpacing = cardSize.width * 0.25
        let fanWidth = fanSpacing * CGFloat(max(0, visibleWaste.count - 1))

        ZStack(alignment: .topTrailing) {
            PilePlaceholderView(cardSize: cardSize)
            ForEach(Array(visibleWaste.enumerated()), id: \.element.id) { index, card in
                let isTopCard = index == visibleWaste.count - 1
                let isDragged = isTopCard && viewModel.isDragging && viewModel.isSelected(card: card)
                let depth = CGFloat(visibleWaste.count - 1 - index)
                let xOffset = -depth * fanSpacing
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts
                )
                .opacity(isDragged ? 0 : 1)
                .offset(x: xOffset, y: 0)
                .zIndex(isTopCard ? 2 : Double(index))
                .allowsHitTesting(isTopCard)
                .cardFramePreference(card.id, xOffset: xOffset)

                if isTopCard {
                    cardView.gesture(dragGesture(.waste))
                } else {
                    cardView
                }
            }
        }
        .frame(width: cardSize.width + fanWidth, height: cardSize.height, alignment: .trailing)
        .onTapGesture {
            viewModel.handleWasteTap()
        }
        .zIndex(isDragSource || isSelected ? 10 : 0)
        .accessibilityLabel("Waste")
    }
}

private struct FoundationView: View {
    @Bindable var viewModel: SolitaireViewModel
    let index: Int
    let cardSize: CGSize
    let isTargeted: Bool
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
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
            if let card = viewModel.state.foundations[index].last {
                let isDragged = viewModel.isDragging && viewModel.isSelected(card: card)
                CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts
                )
                .opacity(isDragged ? 0 : 1)
                .zIndex(isDragged ? 20 : 0)
                .gesture(dragGesture(.foundation(index)))
                .cardFramePreference(card.id)
            }
        }
        .onTapGesture {
            viewModel.handleFoundationTap(index: index)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [.foundation(index): proxy.frame(in: .named("board"))]
                    )
            }
        )
        .zIndex(isDragSource ? 10 : 0)
        .accessibilityLabel("Foundation \(index + 1)")
    }
}

private struct TableauPileView: View {
    @Bindable var viewModel: SolitaireViewModel
    let pileIndex: Int
    let cardSize: CGSize
    let offset: CGFloat
    let isTargeted: Bool
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
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
        let height = max(cardSize.height, cardSize.height + offset * CGFloat(max(0, pile.count - 1)))
        let highlightYOffset: CGFloat = {
            guard viewModel.isDragging, let selection = viewModel.selection else {
                return offset * CGFloat(pile.count)
            }
            if case .tableau(let sourcePile, let sourceIndex) = selection.source, sourcePile == pileIndex {
                return offset * CGFloat(sourceIndex)
            }
            return offset * CGFloat(pile.count)
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
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled,
                    cardTilts: $cardTilts
                )
                .opacity(isDragged ? 0 : 1)
                .offset(x: 0, y: offset * CGFloat(index))
                .zIndex(isDragged ? 20 + Double(index) : Double(index))
                .onTapGesture {
                    viewModel.handleTableauTap(pileIndex: pileIndex, cardIndex: index)
                }
                .cardFramePreference(card.id, yOffset: offset * CGFloat(index))

                cardView.gesture(dragGesture(.tableau(pile: pileIndex, index: index)))
            }
        }
        .frame(width: cardSize.width, height: height, alignment: .top)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: DropTargetFrameKey.self,
                        value: [
                            .tableau(pileIndex): CGRect(
                                x: proxy.frame(in: .named("board")).minX,
                                y: proxy.frame(in: .named("board")).minY + highlightYOffset,
                                width: cardSize.width,
                                height: cardSize.height
                            )
                        ]
                    )
            }
        )
        .zIndex(isDragSource ? 10 : 0)
        .accessibilityLabel("Tableau \(pileIndex + 1)")
    }
}

private struct CardView: View {
    let card: Card
    let isSelected: Bool
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    @State private var flipRotation: Double
    @State private var tiltAngle: Double = 0

    init(card: Card, isSelected: Bool, cardSize: CGSize, isCardTiltEnabled: Bool, cardTilts: Binding<[UUID: Double]>) {
        self.card = card
        self.isSelected = isSelected
        self.cardSize = cardSize
        self.isCardTiltEnabled = isCardTiltEnabled
        self._cardTilts = cardTilts
        _flipRotation = State(initialValue: card.isFaceUp ? 0 : 180)
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

private struct CardBackPattern: View {
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

private struct CardBackView: View {
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

private struct PilePlaceholderView: View {
    let cardSize: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: cardSize.width * 0.12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            .frame(width: cardSize.width, height: cardSize.height)
    }
}

private struct DropHighlightView: View {
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

private struct TableBackground: View {
    @AppStorage(SettingsKey.tableBackgroundColor) private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue

    var body: some View {
        (TableBackgroundColor(rawValue: tableBackgroundColorRawValue) ?? TableBackgroundColor.defaultValue).color
            .ignoresSafeArea()
    }
}

private struct WinOverlay: View {
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

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
