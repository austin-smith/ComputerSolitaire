import SwiftUI
import SwiftData

struct DropTargetFrameKey: PreferenceKey {
    static var defaultValue: [DropTarget: DropTargetGeometry] = [:]

    static func reduce(
        value: inout [DropTarget: DropTargetGeometry],
        nextValue: () -> [DropTarget: DropTargetGeometry]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct StockFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct WasteFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct CardFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CardFramePreference: ViewModifier {
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

extension View {
    func cardFramePreference(_ cardID: UUID, xOffset: CGFloat = 0, yOffset: CGFloat = 0) -> some View {
        modifier(CardFramePreference(cardID: cardID, xOffset: xOffset, yOffset: yOffset))
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
#if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
#endif

    @State private var viewModel = SolitaireViewModel()
    @State private var hapticFeedback = HapticManager.shared
    @State private var dropFrames: [DropTarget: DropTargetGeometry] = [:]
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
    @State private var stockFrame: CGRect = .zero
    @State private var wasteFrame: CGRect = .zero
    @State private var drawAnimationCards: [DrawAnimationCard] = []
    @State private var drawingCardIDs: Set<UUID> = []
    @State private var drawAnimationToken = UUID()
    @State private var undoAnimationItems: [UndoAnimationItem] = []
    @State private var undoAnimationTargets: [UUID: UndoAnimationEndTarget] = [:]
    @State private var undoAnimationProgress: CGFloat = 0
    @State private var isUndoAnimating = false
    @State private var hiddenCardIDs: Set<UUID> = []
    @State private var wasteFanProgress: [UUID: Double] = [:]
    @State private var previousWasteCount: Int = 0
    @State private var previousStockCount: Int = 0
    @State private var hasLoadedGame = false
    @State private var isHydratingGame = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isAutoFinishing = false
    @State private var isShowingRulesAndScoring = false
    @State private var isShowingStats = false
    @State private var timeScoringPauseReasons: Set<TimeScoringPauseReason> = []

    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue

    private var drawMode: DrawMode {
        DrawMode(rawValue: drawModeRawValue) ?? .three
    }

    private enum TimeScoringPauseReason: Hashable {
        case lifecycle
        case menuPresentation
    }

    private var isAnyMenuPresented: Bool {
        isShowingSettings || isShowingRulesAndScoring || isShowingStats
    }

    private var shouldPauseForLifecycle: Bool {
        if scenePhase != .active {
            return true
        }
#if os(macOS)
        return !appearsActive
#else
        return false
#endif
    }

    var body: some View {
        GeometryReader { geometry in
#if os(iOS)
            let metrics = Layout.metrics(for: geometry.size, isRegularWidth: horizontalSizeClass == .regular)
#else
            let metrics = Layout.metrics(for: geometry.size)
#endif
            let cardSize = metrics.cardSize
            let boardContentWidth = (cardSize.width * 7) + (metrics.columnSpacing * 6)
            let isBoardReady = hasLoadedGame && !isHydratingGame
#if os(iOS)
            let isPadLandscape = horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
#endif

            ZStack {
                TableBackground()
                if isBoardReady {
                    VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HeaderView(
                                movesCount: viewModel.movesCount,
                                elapsedSeconds: viewModel.elapsedActiveSeconds(at: context.date),
                                score: viewModel.displayScore(at: context.date),
                                onScoreTapped: { isShowingStats = true }
                            )
                            .frame(width: boardContentWidth, alignment: .leading)
                        }
                        TopRowView(
                            viewModel: viewModel,
                            cardSize: cardSize,
                            columnSpacing: metrics.columnSpacing,
                            wasteFanSpacing: metrics.wasteFanSpacing,
                            activeTarget: activeTarget,
                            isCardTiltEnabled: isCardTiltEnabled,
                            cardTilts: $cardTilts,
                            hiddenCardIDs: hiddenCardIDs,
                            drawingCardIDs: drawingCardIDs,
                            fanProgress: wasteFanProgress,
                            dragGesture: dragGesture(for:)
                        )
                        .frame(width: boardContentWidth, alignment: .leading)
                        TableauRowView(
                            viewModel: viewModel,
                            cardSize: cardSize,
                            columnSpacing: metrics.columnSpacing,
                            faceDownOffset: metrics.tableauFaceDownOffset,
                            faceUpOffset: metrics.tableauFaceUpOffset,
                            activeTarget: activeTarget,
                            isCardTiltEnabled: isCardTiltEnabled,
                            cardTilts: $cardTilts,
                            hiddenCardIDs: hiddenCardIDs,
                            dragGesture: dragGesture(for:)
                        )
                        .frame(width: boardContentWidth, alignment: .leading)
                        Spacer(minLength: 0)
                    }
#if os(iOS)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: isPadLandscape ? .top : .topLeading
                    )
#else
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
#endif
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)

                    if viewModel.isWin {
                        WinOverlay(score: viewModel.score) {
                            stopAutoFinish()
                            viewModel.newGame(drawMode: drawMode)
                            persistGameNow()
                        }
                        .transition(.opacity)
                    }

                    Button("Cancel Drag") {
                        handleEscape()
                    }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "board")
            .sensoryFeedback(trigger: hapticFeedback.trigger) {
                hapticFeedback.feedbackForTrigger
            }
            .onPreferenceChange(DropTargetFrameKey.self) { frames in
                dropFrames = frames
            }
            .onPreferenceChange(StockFrameKey.self) { frame in
                stockFrame = frame
            }
            .onPreferenceChange(WasteFrameKey.self) { frame in
                wasteFrame = frame
            }
            .onPreferenceChange(CardFrameKey.self) { frames in
                cardFrames = frames
            }
            .onChange(of: viewModel.state.waste.count) { _, newValue in
                let stockCount = viewModel.state.stock.count
                if newValue == 0 {
                    drawAnimationCards = []
                    drawingCardIDs = []
                    wasteFanProgress = [:]
                    previousWasteCount = 0
                    previousStockCount = stockCount
                    return
                }
                let addedCount = max(0, newValue - previousWasteCount)
                let newCards = addedCount > 0 ? Array(viewModel.state.waste.suffix(addedCount)) : []
                syncFanProgress(with: viewModel.state.waste, excluding: Set(newCards.map(\.id)))
                if addedCount > 0, stockCount < previousStockCount {
                    prepareFan(for: newCards)
                    let travelDelay = startDrawAnimation(for: newCards, cardSize: cardSize)
                    animateFan(for: newCards, delay: travelDelay)
                }
                previousWasteCount = newValue
                previousStockCount = stockCount
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.state)
            .animation(.easeInOut(duration: 0.12), value: activeTarget)
            .overlay {
                GeometryReader { _ in
                    ZStack {
                        DrawOverlayView(
                            cards: drawAnimationCards,
                            cardSize: cardSize
                        )
                        .zIndex(50)
                        UndoOverlayView(
                            items: undoAnimationItems,
                            progress: undoAnimationProgress
                        )
                        .zIndex(75)
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
                        .zIndex(100)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .toolbar {
#if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button("New Game", systemImage: "plus") {
                        stopAutoFinish()
                        viewModel.newGame(drawMode: drawMode)
                        persistGameNow()
                    }
                    Button("Redeal", systemImage: "arrow.clockwise") {
                        stopAutoFinish()
                        viewModel.redeal()
                        persistGameNow()
                    }
                    Button("Auto Finish", systemImage: "bolt") {
                        startAutoFinish()
                    }
                    .disabled(isAutoFinishDisabled)
                } label: {
                    Label("Game", systemImage: "ellipsis.circle")
                }
                Button {
                    stopAutoFinish()
                    beginUndoAnimationIfNeeded()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(isUndoDisabled)
                Spacer(minLength: 0)
                Button {
                    isShowingStats = true
                } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
#endif
#if os(macOS)
            ToolbarItemGroup(placement: .automatic) {
                Button("New Game") {
                    stopAutoFinish()
                    viewModel.newGame(drawMode: drawMode)
                    persistGameNow()
                }
                Button("Redeal") {
                    stopAutoFinish()
                    viewModel.redeal()
                    persistGameNow()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    stopAutoFinish()
                    beginUndoAnimationIfNeeded()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .labelStyle(.iconOnly)
                .help("Undo")
                .disabled(isUndoDisabled)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    startAutoFinish()
                } label: {
                    Label("Auto Finish", systemImage: "bolt")
                }
                .help("Auto Finish")
                .disabled(isAutoFinishDisabled)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingStats = true
                } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }
                .help("Statistics")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
#endif
        }
        .sheet(isPresented: $isShowingSettings) {
#if os(iOS)
            NavigationStack {
                SettingsView()
            }
#else
            SettingsView()
#endif
        }
        .sheet(isPresented: $isShowingRulesAndScoring) {
            NavigationStack {
                RulesAndScoringView()
            }
        }
        .sheet(isPresented: $isShowingStats) {
#if os(iOS)
            NavigationStack {
                StatsView(viewModel: viewModel)
            }
#else
            StatsView(viewModel: viewModel)
#endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            isShowingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRulesAndScoring)) { _ in
            isShowingRulesAndScoring = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openStatistics)) { _ in
            isShowingStats = true
        }
        .onChange(of: drawModeRawValue) { (_, newValue: Int) in
            let mode = DrawMode(rawValue: newValue) ?? .three
            viewModel.updateDrawMode(mode)
            scheduleAutosave()
        }
        .onChange(of: isAnyMenuPresented) { _, _ in
            updateMenuPresentationPauseState()
        }
        .onChange(of: viewModel.state) { _, _ in
            scheduleAutosave()
            queueAutoFinishStepIfPossible()
        }
        .onChange(of: viewModel.movesCount) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: viewModel.stockDrawCount) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: viewModel.pendingAutoMove?.id) { _, _ in
            processPendingAutoMoveIfPossible()
            queueAutoFinishStepIfPossible()
        }
        .onChange(of: isDroppingCards) { _, _ in
            processPendingAutoMoveIfPossible()
            queueAutoFinishStepIfPossible()
        }
        .onChange(of: isReturningDrag) { _, _ in
            processPendingAutoMoveIfPossible()
            queueAutoFinishStepIfPossible()
        }
        .onChange(of: isUndoAnimating) { _, _ in
            processPendingAutoMoveIfPossible()
            queueAutoFinishStepIfPossible()
        }
        .onChange(of: scenePhase) { _, _ in
            syncLifecyclePauseState()
        }
#if os(macOS)
        .onChange(of: appearsActive) { _, _ in
            syncLifecyclePauseState()
        }
#endif
        .onAppear {
            initializeGameIfNeeded()
        }
        .onDisappear {
            persistGameNow()
        }
    }

    private var isUndoDisabled: Bool {
        !viewModel.canUndo || isUndoAnimating || isDroppingCards || isReturningDrag || viewModel.isDragging
    }

    private var isAutoFinishDisabled: Bool {
        !viewModel.isAutoFinishAvailable
            || isUndoAnimating
            || isDroppingCards
            || isReturningDrag
            || viewModel.isDragging
            || viewModel.pendingAutoMove != nil
    }

    private func startAutoFinish() {
        guard !isAutoFinishDisabled else { return }
        isAutoFinishing = true
        queueAutoFinishStepIfPossible()
    }

    private func stopAutoFinish() {
        guard isAutoFinishing else { return }
        isAutoFinishing = false
        DispatchQueue.main.async {
            viewModel.refreshAutoFinishAvailability()
        }
    }

    private func queueAutoFinishStepIfPossible() {
        guard isAutoFinishing else { return }

        if viewModel.isWin || !viewModel.isAutoFinishAvailable {
            stopAutoFinish()
            return
        }
        guard !isDroppingCards, !isReturningDrag, !isUndoAnimating else { return }
        guard !viewModel.isDragging else { return }
        guard viewModel.pendingAutoMove == nil else { return }

        if !viewModel.queueNextAutoFinishMove() {
            stopAutoFinish()
        }
    }

    private func handleEscape() {
        guard viewModel.isDragging, !isReturningDrag, !isDroppingCards else { return }
        activeTarget = nil
        beginReturnAnimation()
    }

    private func processPendingAutoMoveIfPossible() {
        guard let request = viewModel.pendingAutoMove else { return }
        guard !isDroppingCards, !isReturningDrag, !isUndoAnimating else { return }
        guard !viewModel.isDragging else { return }

        viewModel.clearPendingAutoMove()
        dragTranslation = .zero
        dragReturnOffset = .zero
        activeTarget = nil
        viewModel.selection = request.selection
        viewModel.isDragging = true

        if let firstCard = request.selection.cards.first {
            overlayTilt = cardTilts[firstCard.id] ?? 0
            let tiltSettleDuration = isAutoFinishing ? 0.1 : 0.15
            withAnimation(.easeOut(duration: tiltSettleDuration)) {
                overlayTilt = 0
            }
        }

        beginDropAnimation(
            to: dropTarget(for: request.destination),
            destination: request.destination
        )
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
        stopAutoFinish()
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
            HapticManager.shared.play(.cardPickUp)
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
              let targetFrame = dropFrames[target]?.snapFrame else {
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

        let dropDuration = isAutoFinishing ? 0.18 : 0.25
        withAnimation(.spring(response: dropDuration, dampingFraction: 0.85)) {
            dropAnimationOffset = offsetToTarget
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + dropDuration) {
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
            if !isAutoFinishing {
                DispatchQueue.main.async {
                    viewModel.refreshAutoFinishAvailability()
                }
            }
            processPendingAutoMoveIfPossible()
        }
    }

    private func beginReturnAnimation() {
        guard !isReturningDrag else { return }
        SoundManager.shared.play(.invalidDrop)
        HapticManager.shared.play(.invalidDrop)
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
            processPendingAutoMoveIfPossible()
        }
    }

    private func syncFanProgress(with waste: [Card], excluding excluded: Set<UUID>) {
        let ids = Set(waste.map(\.id))
        wasteFanProgress = wasteFanProgress.filter { ids.contains($0.key) }
        for card in waste where wasteFanProgress[card.id] == nil && !excluded.contains(card.id) {
            wasteFanProgress[card.id] = 1
        }
    }

    private func prepareFan(for newCards: [Card]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for card in newCards {
                wasteFanProgress[card.id] = 0
            }
        }
    }

    private func animateFan(for newCards: [Card], delay: Double) {
        for (index, card) in newCards.enumerated() {
            let stagger = 0.04 * Double(index)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82).delay(delay + stagger)) {
                wasteFanProgress[card.id] = 1
            }
        }
    }

    private func startDrawAnimation(for newCards: [Card], cardSize: CGSize) -> Double {
        guard let plan = DrawAnimationCoordinator.makeDrawPlan(
            newCards: newCards,
            cardSize: cardSize,
            stockFrame: stockFrame,
            wasteFrame: wasteFrame
        ) else {
            return 0
        }

        drawAnimationCards = plan.cards
        drawingCardIDs = plan.cardIDs
        drawAnimationToken = plan.token

        DispatchQueue.main.asyncAfter(deadline: .now() + plan.travelDuration + plan.totalDelay) {
            guard drawAnimationToken == plan.token else { return }
            drawAnimationCards = []
            drawingCardIDs = []
        }
        return plan.travelDuration + plan.totalDelay
    }


    private func destination(for target: DropTarget) -> Destination {
        switch target {
        case .foundation(let index):
            return .foundation(index)
        case .tableau(let index):
            return .tableau(index)
        }
    }

    private func dropTarget(for destination: Destination) -> DropTarget {
        switch destination {
        case .foundation(let index):
            return .foundation(index)
        case .tableau(let index):
            return .tableau(index)
        }
    }

    private func dropTarget(at location: CGPoint) -> DropTarget? {
        DragDropCoordinator.resolveDropTarget(
            at: location,
            dropFrames: dropFrames
        ) { target in
            viewModel.canDrop(to: destination(for: target))
        }
    }

    private func beginUndoAnimationIfNeeded() {
        guard !isUndoAnimating else { return }
        guard !viewModel.isDragging, !isDroppingCards, !isReturningDrag else { return }
        guard !viewModel.isWin else { return }
        guard let snapshot = viewModel.peekUndoSnapshot() else { return }
        HapticManager.shared.play(.undoMove)

        let currentFrames = cardFrames
        let beforeState = viewModel.state
        let beforeCards = cardLookup(in: beforeState)
        let afterCards = cardLookup(in: snapshot.state)

        if snapshot.undoContext?.action == .flipTableauTop {
            viewModel.undo()
            return
        }

        let (startingItems, targets, needsPostUndoFrames): ([UndoAnimationItem], [UUID: UndoAnimationEndTarget], Bool) = {
            if let context = snapshot.undoContext {
                return buildUndoAnimationPlan(
                    context: context,
                    beforeCards: beforeCards,
                    afterCards: afterCards,
                    startingFrames: currentFrames
                )
            }
            return buildFallbackUndoAnimationPlan(
                beforeState: beforeState,
                afterState: snapshot.state,
                beforeCards: beforeCards,
                afterCards: afterCards,
                startingFrames: currentFrames
            )
        }()

        guard !startingItems.isEmpty else {
            viewModel.undo()
            return
        }

        undoAnimationItems = startingItems
        undoAnimationTargets = targets
        undoAnimationProgress = 0
        isUndoAnimating = true
        hiddenCardIDs = Set(startingItems.map(\.id))
        if needsPostUndoFrames {
            cardFrames = [:]
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.undo()
        }

        if needsPostUndoFrames {
            DispatchQueue.main.async {
                resolveUndoAnimationTargets(attemptsRemaining: 24)
            }
        } else {
            resolveUndoAnimationTargets(attemptsRemaining: 0)
        }
    }

    private func buildUndoAnimationPlan(
        context: UndoAnimationContext,
        beforeCards: [UUID: Card],
        afterCards: [UUID: Card],
        startingFrames: [UUID: CGRect]
    ) -> (items: [UndoAnimationItem], targets: [UUID: UndoAnimationEndTarget], needsPostUndoFrames: Bool) {
        let plan = UndoAnimationCoordinator.buildPlan(
            context: context,
            beforeCards: beforeCards,
            afterCards: afterCards,
            cardFrames: startingFrames,
            stockFrame: stockFrame,
            wasteFrame: wasteFrame
        )
        return (plan.items, plan.targets, plan.needsPostUndoFrames)
    }

    private func resolveUndoTargetFrame(_ target: UndoAnimationEndTarget) -> CGRect? {
        UndoAnimationCoordinator.resolveTargetFrame(
            target,
            cardFrames: cardFrames,
            stockFrame: stockFrame
        )
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        UndoAnimationCoordinator.framesApproximatelyEqual(lhs, rhs)
    }

    private func resolveUndoAnimationTargets(attemptsRemaining: Int) {
        let resolvedItems = undoAnimationItems.compactMap { item -> UndoAnimationItem? in
            guard let target = undoAnimationTargets[item.id], let endFrame = resolveUndoTargetFrame(target) else { return nil }
            return UndoAnimationItem(id: item.id, card: item.card, startFrame: item.startFrame, endFrame: endFrame)
        }

        let hasMovement = resolvedItems.contains { item in
            !framesApproximatelyEqual(item.startFrame, item.endFrame)
        }

        if !resolvedItems.isEmpty, hasMovement {
            undoAnimationItems = resolvedItems
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                undoAnimationProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                finishUndoAnimation()
            }
            return
        }

        guard attemptsRemaining > 0 else {
            finishUndoAnimation()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            resolveUndoAnimationTargets(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private func finishUndoAnimation() {
        undoAnimationItems = []
        undoAnimationTargets = [:]
        undoAnimationProgress = 0
        hiddenCardIDs = []
        isUndoAnimating = false
        processPendingAutoMoveIfPossible()
    }

    private func cardLookup(in state: GameState) -> [UUID: Card] {
        var lookup: [UUID: Card] = [:]
        for card in state.stock { lookup[card.id] = card }
        for card in state.waste { lookup[card.id] = card }
        for pile in state.foundations {
            for card in pile { lookup[card.id] = card }
        }
        for pile in state.tableau {
            for card in pile { lookup[card.id] = card }
        }
        return lookup
    }

    private enum CardLocation: Equatable {
        case stock(Int)
        case waste(Int)
        case foundation(pile: Int, index: Int)
        case tableau(pile: Int, index: Int)
    }

    private func cardLocations(in state: GameState) -> [UUID: CardLocation] {
        var locations: [UUID: CardLocation] = [:]

        for (index, card) in state.stock.enumerated() {
            locations[card.id] = .stock(index)
        }
        for (index, card) in state.waste.enumerated() {
            locations[card.id] = .waste(index)
        }
        for (pile, cards) in state.foundations.enumerated() {
            for (index, card) in cards.enumerated() {
                locations[card.id] = .foundation(pile: pile, index: index)
            }
        }
        for (pile, cards) in state.tableau.enumerated() {
            for (index, card) in cards.enumerated() {
                locations[card.id] = .tableau(pile: pile, index: index)
            }
        }

        return locations
    }

    private func buildFallbackUndoAnimationPlan(
        beforeState: GameState,
        afterState: GameState,
        beforeCards: [UUID: Card],
        afterCards: [UUID: Card],
        startingFrames: [UUID: CGRect]
    ) -> (items: [UndoAnimationItem], targets: [UUID: UndoAnimationEndTarget], needsPostUndoFrames: Bool) {
        let beforeLocations = cardLocations(in: beforeState)
        let afterLocations = cardLocations(in: afterState)
        let ids = Set(beforeLocations.keys).union(afterLocations.keys).filter { id in
            shouldAnimateFallbackTransition(from: beforeLocations[id], to: afterLocations[id])
        }

        var items: [UndoAnimationItem] = []
        var targets: [UUID: UndoAnimationEndTarget] = [:]

        for id in ids {
            guard let card = beforeCards[id] ?? afterCards[id] else { continue }
            let startFrame: CGRect? = {
                if let frame = startingFrames[id] { return frame }
                if case .stock(let index)? = beforeLocations[id] {
                    return UndoAnimationCoordinator.stockAnchorFrame(for: index, stockFrame: stockFrame)
                }
                return nil
            }()

            guard let startFrame else { continue }

            items.append(
                UndoAnimationItem(
                    id: id,
                    card: card,
                    startFrame: startFrame,
                    endFrame: startFrame
                )
            )

            if case .stock(let index)? = afterLocations[id] {
                targets[id] = .stock(index)
            } else {
                targets[id] = .card(id)
            }
        }

        let needsPostUndoFrames = targets.values.contains { target in
            if case .card = target { return true }
            return false
        }

        return (items, targets, needsPostUndoFrames)
    }

    private func shouldAnimateFallbackTransition(
        from before: CardLocation?,
        to after: CardLocation?
    ) -> Bool {
        guard before != after else { return false }

        switch (before, after) {
        case (.none, _), (_, .none):
            return false
        case (.some(.stock(_)), .some(.stock(_))),
             (.some(.waste(_)), .some(.waste(_))):
            return false
        default:
            return true
        }
    }

    private func initializeGameIfNeeded() {
        guard !hasLoadedGame else { return }
        hasLoadedGame = true
        isHydratingGame = true
        defer {
            isHydratingGame = false
            previousWasteCount = viewModel.state.waste.count
            previousStockCount = viewModel.state.stock.count
        }

        if let payload = GamePersistence.load(from: modelContext), viewModel.restore(from: payload) {
            if drawModeRawValue != viewModel.stockDrawCount {
                drawModeRawValue = viewModel.stockDrawCount
            }
        } else {
            viewModel.newGame(drawMode: drawMode)
            persistGameNow()
        }

        timeScoringPauseReasons = []
        if shouldPauseForLifecycle {
            timeScoringPauseReasons.insert(.lifecycle)
        }
        if isAnyMenuPresented {
            timeScoringPauseReasons.insert(.menuPresentation)
        }
        let shouldPauseTimeScoring = !timeScoringPauseReasons.isEmpty
        let didChange = shouldPauseTimeScoring
            ? viewModel.pauseTimeScoring()
            : viewModel.resumeTimeScoring()
        if didChange {
            persistGameNow()
        }
    }

    private func scheduleAutosave() {
        guard hasLoadedGame, !isHydratingGame else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            persistGameNow()
        }
    }

    private func syncLifecyclePauseState() {
        updatePauseReason(.lifecycle, shouldPause: shouldPauseForLifecycle)
    }

    private func updateMenuPresentationPauseState() {
        updatePauseReason(.menuPresentation, shouldPause: isAnyMenuPresented)
    }

    private func updatePauseReason(_ reason: TimeScoringPauseReason, shouldPause: Bool) {
        guard hasLoadedGame else { return }
        let wasPaused = !timeScoringPauseReasons.isEmpty
        if shouldPause {
            timeScoringPauseReasons.insert(reason)
        } else {
            timeScoringPauseReasons.remove(reason)
        }
        let isPaused = !timeScoringPauseReasons.isEmpty
        guard wasPaused != isPaused else { return }
        let didChange = isPaused
            ? viewModel.pauseTimeScoring()
            : viewModel.resumeTimeScoring()
        if didChange {
            persistGameNow()
        }
    }

    private func persistGameNow() {
        guard hasLoadedGame else { return }
        autosaveTask?.cancel()
        autosaveTask = nil
        do {
            try GamePersistence.save(viewModel.persistencePayload(), in: modelContext)
        } catch {
#if DEBUG
            print("Failed to persist game state: \(error)")
#endif
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
