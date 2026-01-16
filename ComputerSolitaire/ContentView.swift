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

struct ContentView: View {
    @State private var viewModel = SolitaireViewModel()
    @State private var dropFrames: [DropTarget: CGRect] = [:]
    @State private var activeTarget: DropTarget?
    @State private var dragTranslation: CGSize = .zero
    @State private var isShowingSettings = false

    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true

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
                        dragTranslation: dragTranslation,
                        activeTarget: activeTarget,
                        isCardTiltEnabled: isCardTiltEnabled,
                        dragGesture: dragGesture(for:)
                    )
                    TableauRowView(
                        viewModel: viewModel,
                        cardSize: cardSize,
                        tableauOffset: tableauOffset,
                        dragTranslation: dragTranslation,
                        activeTarget: activeTarget,
                        isCardTiltEnabled: isCardTiltEnabled,
                        dragGesture: dragGesture(for:)
                    )
                    Spacer(minLength: 0)
                }
                .padding(24)

                if viewModel.isWin {
                    WinOverlay {
                        viewModel.newGame()
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "board")
            .onPreferenceChange(DropTargetFrameKey.self) { frames in
                dropFrames = frames
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.state)
            .animation(.easeInOut(duration: 0.12), value: viewModel.selection)
            .animation(.easeOut(duration: 0.15), value: viewModel.isDragging)
            .animation(.easeInOut(duration: 0.12), value: activeTarget)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("New Game") {
                    viewModel.newGame()
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
        switch origin {
        case .waste:
            return viewModel.startDragFromWaste()
        case .foundation(let index):
            return viewModel.startDragFromFoundation(index: index)
        case .tableau(let pile, let index):
            return viewModel.startDragFromTableau(pileIndex: pile, cardIndex: index)
        }
    }

    private func finishDrag() {
        guard viewModel.isDragging else {
            dragTranslation = .zero
            activeTarget = nil
            return
        }

        let target = activeTarget
        activeTarget = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            dragTranslation = .zero
            if let target {
                viewModel.handleDrop(to: destination(for: target))
            } else {
                viewModel.cancelDrag()
            }
        }
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
    let dragTranslation: CGSize
    let activeTarget: DropTarget?
    let isCardTiltEnabled: Bool
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(spacing: 20) {
            StockView(viewModel: viewModel, cardSize: cardSize)
            WasteView(
                viewModel: viewModel,
                cardSize: cardSize,
                dragTranslation: dragTranslation,
                isCardTiltEnabled: isCardTiltEnabled,
                dragGesture: dragGesture
            )
            Spacer()
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    FoundationView(
                        viewModel: viewModel,
                        index: index,
                        cardSize: cardSize,
                        dragTranslation: dragTranslation,
                        isTargeted: activeTarget == .foundation(index),
                        isCardTiltEnabled: isCardTiltEnabled,
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
    let dragTranslation: CGSize
    let activeTarget: DropTarget?
    let isCardTiltEnabled: Bool
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        HStack(alignment: .top, spacing: Layout.tableauSpacing) {
            ForEach(0..<7, id: \.self) { index in
                TableauPileView(
                    viewModel: viewModel,
                    pileIndex: index,
                    cardSize: cardSize,
                    offset: tableauOffset,
                    dragTranslation: dragTranslation,
                    isTargeted: activeTarget == .tableau(index),
                    isCardTiltEnabled: isCardTiltEnabled,
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
    let dragTranslation: CGSize
    let isCardTiltEnabled: Bool
    let dragGesture: (DragOrigin) -> AnyGesture<DragGesture.Value>

    var body: some View {
        let isDragSource: Bool = {
            guard viewModel.isDragging, let selection = viewModel.selection else { return false }
            if case .waste = selection.source {
                return true
            }
            return false
        }()
        let visibleWaste = viewModel.state.waste.suffix(3)
        let isSelected = visibleWaste.contains(where: { viewModel.isSelected(card: $0) })
        let fanSpacing = cardSize.width * 0.25
        let fanWidth = fanSpacing * CGFloat(max(0, visibleWaste.count - 1))

        ZStack(alignment: .topTrailing) {
            PilePlaceholderView(cardSize: cardSize)
            ForEach(Array(visibleWaste.enumerated()), id: \.element.id) { index, card in
                let isTopCard = index == visibleWaste.count - 1
                let isDragged = isTopCard && viewModel.isDragging && viewModel.isSelected(card: card)
                let dragOffset = isDragged ? dragTranslation : .zero
                let depth = CGFloat(visibleWaste.count - 1 - index)
                let xOffset = -depth * fanSpacing
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled
                )
                .offset(x: xOffset + dragOffset.width, y: dragOffset.height)
                .zIndex(isTopCard ? 2 : Double(index))
                .allowsHitTesting(isTopCard)

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
    let dragTranslation: CGSize
    let isTargeted: Bool
    let isCardTiltEnabled: Bool
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
                let dragOffset = isDragged ? dragTranslation : .zero
                CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled
                )
                .offset(x: dragOffset.width, y: dragOffset.height)
                .zIndex(isDragged ? 20 : 0)
                .gesture(dragGesture(.foundation(index)))
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
    let dragTranslation: CGSize
    let isTargeted: Bool
    let isCardTiltEnabled: Bool
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
                let dragOffset = isDragged ? dragTranslation : .zero
                let cardView = CardView(
                    card: card,
                    isSelected: viewModel.isSelected(card: card),
                    cardSize: cardSize,
                    isCardTiltEnabled: isCardTiltEnabled
                )
                .offset(x: dragOffset.width, y: offset * CGFloat(index) + dragOffset.height)
                .zIndex(isDragged ? 20 + Double(index) : Double(index))
                .onTapGesture {
                    viewModel.handleTableauTap(pileIndex: pileIndex, cardIndex: index)
                }

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
    @State private var flipRotation: Double

    init(card: Card, isSelected: Bool, cardSize: CGSize, isCardTiltEnabled: Bool) {
        self.card = card
        self.isSelected = isSelected
        self.cardSize = cardSize
        self.isCardTiltEnabled = isCardTiltEnabled
        _flipRotation = State(initialValue: card.isFaceUp ? 0 : 180)
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
        let tiltAngle = isCardTiltEnabled ? Double.random(in: CardTilt.angleRange) : 0

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
    }

    private func cardFront(
        cornerRadius: CGFloat,
        borderColor: Color,
        borderWidth: CGFloat,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            cardBase(
                cornerRadius: cornerRadius,
                fill: Color.white,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(card.rank.label)
                    .font(.system(size: cardSize.width * 0.28, weight: .bold, design: .rounded))
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: cardSize.width * 0.22, weight: .semibold))
            }
            .foregroundStyle(card.suit.isRed ? Color.red : Color.black)
            .padding(cardSize.width * 0.12)

            Image(systemName: card.suit.symbolName)
                .font(.system(size: cardSize.width * 0.48, weight: .semibold))
                .foregroundStyle(card.suit.isRed ? Color.red.opacity(0.2) : Color.black.opacity(0.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        ZStack {
            cardBase(
                cornerRadius: cornerRadius,
                fill: Color(red: 0.12, green: 0.32, blue: 0.58),
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
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

private struct CardBackView: View {
    let cardSize: CGSize

    var body: some View {
        let cornerRadius = cardSize.width * 0.12
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(red: 0.12, green: 0.32, blue: 0.58))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            .frame(width: cardSize.width, height: cardSize.height)
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
            }
        }
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
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.25, blue: 0.18),
                Color(red: 0.02, green: 0.18, blue: 0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.12), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
        )
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
