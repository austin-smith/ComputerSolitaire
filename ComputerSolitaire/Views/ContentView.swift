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

struct BoardContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
    @State private var wasteReturnAnchorCardID: UUID?
    @State private var wasteReturnAnchorFrame: CGRect?
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
    @State private var boardContentSize: CGSize = .zero
    @State private var boardViewportSize: CGSize = .zero
    @State private var previousWasteCount: Int = 0
    @State private var previousStockCount: Int = 0
    @State private var hasLoadedGame = false
    @State private var isHydratingGame = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isAutoFinishing = false
    @State private var isShowingRulesAndScoring = false
    @State private var rulesAndScoringInitialSection: RulesAndScoringView.Section = .rules
    @State private var isShowingStats = false
    @State private var timeScoringPauseReasons: Set<TimeScoringPauseReason> = []
    @State private var hintHighlightOpacity: Double = 0
    @State private var winCelebration = WinCelebrationController()

    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue
    @AppStorage(SettingsKey.showHintButton) private var isHintButtonVisible = true

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
        sceneDecorations(
            for: AnyView(
                GeometryReader { geometry in
                    boardRoot(for: geometry)
                }
            )
        )
    }

    private func sceneDecorations(for baseView: AnyView) -> some View {
        let toolbarView = applyToolbar(to: baseView)
        let sheetsView = applySheets(to: toolbarView)
        return applyObservers(to: sheetsView)
    }

    private func applyToolbar(to view: AnyView) -> AnyView {
        AnyView(
            view.toolbar {
#if os(iOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu {
                        Button("New Game", systemImage: "plus") {
                            startNewGameFromUI()
                        }
                        Button("Redeal", systemImage: "arrow.clockwise") {
                            redealFromUI()
                        }
                        Button("Auto Finish", systemImage: "bolt") {
                            startAutoFinish()
                        }
                        .disabled(isAutoFinishDisabled)
                        if isHintButtonVisible {
                            Button("Hint", systemImage: "lightbulb") {
                                triggerHint()
                            }
                            .disabled(isHintDisabled)
                        }
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
                        startNewGameFromUI()
                    }
                    Button("Redeal") {
                        redealFromUI()
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
                if isHintButtonVisible {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            triggerHint()
                        } label: {
                            Label("Hint", systemImage: "lightbulb")
                        }
                        .help("Hint")
                        .keyboardShortcut("h", modifiers: [])
                        .disabled(isHintDisabled)
                    }
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
        )
    }

    private func applySheets(to view: AnyView) -> AnyView {
        AnyView(
            view.sheet(isPresented: $isShowingSettings) {
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
                    RulesAndScoringView(initialSection: rulesAndScoringInitialSection)
                }
            }
            .sheet(isPresented: $isShowingStats) {
#if os(iOS)
                NavigationStack {
                    StatisticsView(viewModel: viewModel)
                }
#else
                StatisticsView(viewModel: viewModel)
#endif
            }
        )
    }

    private func applyObservers(to view: AnyView) -> AnyView {
        AnyView(
            view
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                isShowingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRulesAndScoring)) { _ in
                presentRulesAndScoring(initialSection: .rules)
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
            .onChange(of: viewModel.hasActiveHint) { _, hasActiveHint in
                if !hasActiveHint {
                    withAnimation(.easeOut(duration: 0.3)) {
                        hintHighlightOpacity = 0
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        hintHighlightOpacity = 1
                    }
                }
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
                winCelebration.cancelTask()
                persistGameNow()
            }
        )
    }

    @ViewBuilder
    private func boardRoot(for geometry: GeometryProxy) -> some View {
#if os(iOS)
        let metrics = Layout.metrics(for: geometry.size, isRegularWidth: horizontalSizeClass == .regular)
#else
        let metrics = Layout.metrics(for: geometry.size)
#endif
        let cardSize = metrics.cardSize
        let boardScaleFactor = boardScaleFactor(for: geometry.size)
        let effectiveCardSize = CGSize(width: cardSize.width * boardScaleFactor, height: cardSize.height * boardScaleFactor)
        let boardContentWidth = (cardSize.width * 7) + (metrics.columnSpacing * 6)
        let isBoardReady = hasLoadedGame && !isHydratingGame
        let hintedTarget: DropTarget? = {
            guard let destination = viewModel.hintedDestination else { return nil }
            return dropTarget(for: destination)
        }()
        let openScoringDetails: () -> Void = { presentRulesAndScoring(initialSection: .scoring) }
#if os(iOS)
        let isPadLandscape = horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
#endif

        ZStack {
            TableBackground()
            if isBoardReady {
                let boardLayout = VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let headerMetrics = headerMetrics(at: context.date)
                        headerView(
                            elapsedSeconds: headerMetrics.elapsedSeconds,
                            score: headerMetrics.score,
                            boardContentWidth: boardContentWidth,
                            onScoreTapped: openScoringDetails
                        )
                    }
                    TopRowView(
                        viewModel: viewModel,
                        cardSize: cardSize,
                        columnSpacing: metrics.columnSpacing,
                        wasteFanSpacing: metrics.wasteFanSpacing,
                        activeTarget: activeTarget,
                        hintedTarget: hintedTarget,
                        isStockHinted: viewModel.isStockHinted,
                        isWasteHinted: viewModel.isWasteHinted,
                        hintHighlightOpacity: hintHighlightOpacity,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        hiddenCardIDs: effectiveHiddenCardIDs,
                        hintedCardIDs: viewModel.hintedCardIDs,
                        hintWiggleToken: viewModel.hintWiggleToken,
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
                        hintedTarget: hintedTarget,
                        hintHighlightOpacity: hintHighlightOpacity,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts,
                        hiddenCardIDs: effectiveHiddenCardIDs,
                        hintedCardIDs: viewModel.hintedCardIDs,
                        hintWiggleToken: viewModel.hintWiggleToken,
                        dragGesture: dragGesture(for:)
                    )
                    .frame(width: boardContentWidth, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(!isWinCascadeAnimating)
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

                boardLayout
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: BoardContentSizeKey.self, value: proxy.size)
                        }
                    )
                    .scaleEffect(boardScaleFactor, anchor: .top)

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
            refreshLoadedWinPresentationIfNeeded()
        }
        .onPreferenceChange(StockFrameKey.self) { frame in
            stockFrame = frame
        }
        .onPreferenceChange(WasteFrameKey.self) { frame in
            wasteFrame = frame
        }
        .onPreferenceChange(CardFrameKey.self) { frames in
            if shouldUpdateCardFrames(with: frames) {
                cardFrames = frames
            }
        }
        .onPreferenceChange(BoardContentSizeKey.self) { size in
            boardContentSize = size
        }
        .onAppear {
            boardViewportSize = geometry.size
            refreshLoadedWinPresentationIfNeeded()
        }
        .onChange(of: geometry.size) { _, newSize in
            boardViewportSize = newSize
            refreshLoadedWinPresentationIfNeeded()
        }
        .onChange(of: viewModel.isWin) { _, isWin in
            guard !isHydratingGame else { return }
            if isWin {
                winCelebration.beginIfNeededForWin(
                    foundations: viewModel.state.foundations,
                    dropFrames: dropFrames,
                    boardViewportSize: boardViewportSize
                )
            } else if winCelebration.phase != .idle {
                winCelebration.reset(to: .idle)
            }
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
                let travelDelay = startDrawAnimation(for: newCards, cardSize: effectiveCardSize)
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
                        cardSize: effectiveCardSize
                    )
                    .zIndex(50)
                    UndoOverlayView(
                        items: undoAnimationItems,
                        progress: undoAnimationProgress
                    )
                    .zIndex(75)
                    WinCascadeOverlayView(cards: winCelebration.cards)
                        .zIndex(90)
                    DragOverlayView(
                        viewModel: viewModel,
                        cardFrames: dragOverlayCardFrames,
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
                    if viewModel.isWin && winCelebration.phase != .idle {
                        WinOverlay(score: viewModel.score) {
                            startNewGameFromUI()
                        }
                        .zIndex(200)
                        .transition(.opacity)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func headerMetrics(at date: Date) -> (elapsedSeconds: Int, score: Int) {
        if viewModel.isClockAdvancing {
            return (viewModel.elapsedActiveSeconds(at: date), viewModel.displayScore(at: date))
        }
        return (viewModel.elapsedActiveSeconds(), viewModel.displayScore())
    }

    private func presentRulesAndScoring(initialSection: RulesAndScoringView.Section = .rules) {
        rulesAndScoringInitialSection = initialSection
        isShowingRulesAndScoring = true
    }

    private func headerView(
        elapsedSeconds: Int,
        score: Int,
        boardContentWidth: CGFloat,
        onScoreTapped: @escaping () -> Void
    ) -> some View {
        HeaderView(
            movesCount: viewModel.movesCount,
            elapsedSeconds: elapsedSeconds,
            score: score,
            onScoreTapped: onScoreTapped
        )
        .frame(width: boardContentWidth, alignment: .leading)
    }

    private var effectiveHiddenCardIDs: Set<UUID> {
        hiddenCardIDs.union(winCelebration.hiddenFoundationCardIDs)
    }

    private var isWinCascadeAnimating: Bool {
        winCelebration.isAnimating
    }

    private var isUndoDisabled: Bool {
        !viewModel.canUndo
            || isUndoAnimating
            || isDroppingCards
            || isReturningDrag
            || viewModel.isDragging
            || isWinCascadeAnimating
    }

    private var isAutoFinishDisabled: Bool {
        !viewModel.isAutoFinishAvailable
            || isUndoAnimating
            || isDroppingCards
            || isReturningDrag
            || viewModel.isDragging
            || viewModel.pendingAutoMove != nil
            || isWinCascadeAnimating
    }

    private var isHintDisabled: Bool {
        viewModel.isWin
            || isUndoAnimating
            || isDroppingCards
            || isReturningDrag
            || viewModel.isDragging
            || viewModel.pendingAutoMove != nil
            || !viewModel.isHintAvailable
            || isWinCascadeAnimating
    }

    private func triggerHint() {
        guard !isHintDisabled else { return }
        stopAutoFinish()
        viewModel.requestHint()
    }

    private func startNewGameFromUI() {
        stopAutoFinish()
        winCelebration.reset(to: .idle)
        viewModel.newGame(drawMode: drawMode)
        persistGameNow()
    }

    private func redealFromUI() {
        stopAutoFinish()
        winCelebration.reset(to: .idle)
        viewModel.redeal()
        persistGameNow()
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
        wasteReturnAnchorCardID = nil
        wasteReturnAnchorFrame = nil
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
            if case .waste = origin {
                wasteReturnAnchorCardID = firstCard.id
                wasteReturnAnchorFrame = cardFrames[firstCard.id]
            }
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
            wasteReturnAnchorCardID = nil
            wasteReturnAnchorFrame = nil
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
            wasteReturnAnchorCardID = nil
            wasteReturnAnchorFrame = nil
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
        let isWasteReturn = viewModel.selection?.source == .waste
        let currentTranslation = dragTranslation
        returningCards = viewModel.selection?.cards ?? []
        let targetTilt: Double = {
            guard let firstCard = returningCards.first else { return 0 }
            guard isWasteReturn, isCardTiltEnabled else {
                return cardTilts[firstCard.id] ?? 0
            }
            let rerolledTilt = Double.random(in: CardTilt.angleRange)
            cardTilts[firstCard.id] = rerolledTilt
            return rerolledTilt
        }()
        // Keep viewModel.isDragging true to hide original card during animation
        isReturningDrag = true
        dragReturnOffset = .zero
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            dragReturnOffset = CGSize(width: -currentTranslation.width, height: -currentTranslation.height)
            overlayTilt = targetTilt
        }
        let returnDuration = 0.32
        DispatchQueue.main.asyncAfter(deadline: .now() + returnDuration) {
            viewModel.cancelDrag()
            wasteReturnAnchorCardID = nil
            wasteReturnAnchorFrame = nil
            dragTranslation = .zero
            dragReturnOffset = .zero
            isReturningDrag = false
            returningCards = []
            processPendingAutoMoveIfPossible()
        }
    }

    private var dragOverlayCardFrames: [UUID: CGRect] {
        guard isReturningDrag,
              let returningCard = returningCards.first,
              returningCard.id == wasteReturnAnchorCardID,
              let anchorFrame = wasteReturnAnchorFrame else {
            return cardFrames
        }
        var frames = cardFrames
        frames[returningCard.id] = anchorFrame
        return frames
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

    private func shouldUpdateCardFrames(with newFrames: [UUID: CGRect]) -> Bool {
        guard cardFrames.count == newFrames.count else { return true }
        for (id, frame) in newFrames {
            guard let current = cardFrames[id] else { return true }
            if !framesApproximatelyEqual(current, frame) {
                return true
            }
        }
        return false
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
            winCelebration.reset(to: .idle)
            viewModel.newGame(drawMode: drawMode)
            persistGameNow()
        }
        winCelebration.syncForLoadedGame(
            foundations: viewModel.state.foundations,
            isWin: viewModel.isWin,
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize
        )

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

    private func refreshLoadedWinPresentationIfNeeded() {
        guard hasLoadedGame, viewModel.isWin else { return }
        guard winCelebration.phase == .completed else { return }
        guard winCelebration.cards.isEmpty else { return }
        winCelebration.syncForLoadedGame(
            foundations: viewModel.state.foundations,
            isWin: true,
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize
        )
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

    private func boardScaleFactor(for availableSize: CGSize) -> CGFloat {
        guard boardContentSize.width > 0, boardContentSize.height > 0 else { return 1 }
        let widthScale = availableSize.width / boardContentSize.width
        let heightScale = availableSize.height / boardContentSize.height
        return min(1, widthScale, heightScale)
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
