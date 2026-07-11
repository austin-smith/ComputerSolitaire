import SwiftUI
import SwiftData

// TODO: Split board layout, interaction, animation, lifecycle, and persistence
// coordination along stable ownership boundaries, then remove this exception.
// swiftlint:disable file_length

struct DropTargetFrameKey: PreferenceKey {
    static var defaultValue: [DropTarget: DropTargetGeometry] = [:]

    static func reduce(
        value: inout [DropTarget: DropTargetGeometry],
        nextValue: () -> [DropTarget: DropTargetGeometry]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// Single-frame keys must ignore the default: on macOS, sibling subtrees that
// never set the key still run reduce with .zero, and a last-wins reducer lets
// that erase the real frame (the draw animation then never runs).
struct StockFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct WasteFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
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

private struct HeaderMetrics {
    let elapsedSeconds: Int
    let score: Int
}

private struct BoardPresentation {
    let metrics: Layout.Metrics
    let columnCount: Int
    let contentWidth: CGFloat
    let scale: CGFloat
    let effectiveCardSize: CGSize
    let hintedTarget: DropTarget?
    let centersContent: Bool
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
    @State private var boardViewportSize: CGSize = .zero
    @State private var previousWasteCount: Int = 0
    @State private var previousStockCount: Int = 0
    @State private var hasLoadedGame = false
    @State private var isHydratingGame = false
    // True while a screenshot board is on screen; suppresses autosave so the
    // staged game never overwrites the real one. Only set in DEBUG builds.
    @State private var isScreenshotSession = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isAutoFinishing = false
    @State private var isShowingRulesAndScoring = false
    @State private var rulesAndScoringInitialSection: RulesAndScoringView.Section = .rules
    @State private var isShowingStats = false
    @State private var timeScoringPauseReasons: Set<TimeScoringPauseReason> = []
    @State private var hintHighlightOpacity: Double = 0
    @State private var winCelebration = WinCelebrationController()

    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.gameVariant) private var gameVariantRawValue = GameVariant.klondike.rawValue
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue
    @AppStorage(SettingsKey.showHintButton) private var isHintButtonVisible = true
    @AppStorage(SettingsKey.cardStyle) private var cardStyleRawValue = CardStyle.defaultValue.rawValue

    private var gameVariant: GameVariant {
        GameVariant(rawValue: gameVariantRawValue) ?? .klondike
    }

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

    private var currentCardStyle: CardStyle {
        CardStyle(rawValue: cardStyleRawValue) ?? .defaultValue
    }

    var body: some View {
        sceneDecorations(
            for: GeometryReader { geometry in
                boardRoot(for: geometry)
            }
            .environment(\.cardStyle, currentCardStyle)
        )
    }

}

private extension ContentView {
    func sceneDecorations<Content: View>(for baseView: Content) -> some View {
        let toolbarView = applyToolbar(to: baseView)
        let sheetsView = applySheets(to: toolbarView)
        return applyObservers(to: sheetsView)
    }

    private func applyToolbar<Content: View>(to view: Content) -> some View {
        view
            .toolbar {
                gameToolbar
            }
    }

    @ToolbarContentBuilder
    var gameToolbar: some ToolbarContent {
#if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            Menu {
                Button("New Game", systemImage: "plus") { startNewGameFromUI() }
                Button("Redeal", systemImage: "arrow.clockwise") { redealFromUI() }
                Button("Auto Finish", systemImage: "bolt") { startAutoFinish() }
                    .disabled(isAutoFinishDisabled)
                if isHintButtonVisible {
                    Button("Hint", systemImage: "lightbulb") { triggerHint() }
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
            Button { isShowingStats = true } label: { Label("Statistics", systemImage: "chart.bar") }
            Button { isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        }
#endif
#if os(macOS)
        ToolbarSpacer(.flexible)
        ToolbarItemGroup(placement: .primaryAction) {
            toolbarButton("New Game", systemImage: "plus") { startNewGameFromUI() }
            toolbarButton("Redeal", systemImage: "arrow.clockwise", action: redealFromUI)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup(placement: .primaryAction) {
            toolbarButton("Undo", systemImage: "arrow.uturn.backward") {
                stopAutoFinish()
                beginUndoAnimationIfNeeded()
            }
            .disabled(isUndoDisabled)
            toolbarButton("Auto Finish", systemImage: "bolt", action: startAutoFinish)
                .disabled(isAutoFinishDisabled)
            if isHintButtonVisible {
                toolbarButton("Hint", systemImage: "lightbulb", action: triggerHint)
                    .disabled(isHintDisabled)
            }
            toolbarButton("Statistics", systemImage: "chart.bar") { isShowingStats = true }
            toolbarButton("Settings", systemImage: "gearshape") { isShowingSettings = true }
        }
#endif
    }

#if os(macOS)
    func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
        .help(title)
    }
#endif

    private func applySheets<Content: View>(to view: Content) -> some View {
        view
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
                    RulesAndScoringView(initialSection: rulesAndScoringInitialSection)
                }
            }
            .sheet(isPresented: $isShowingStats) {
#if os(iOS)
                NavigationStack {
                    StatisticsView(viewModel: viewModel, initialVariant: viewModel.gameVariant)
                }
#else
                StatisticsView(viewModel: viewModel, initialVariant: viewModel.gameVariant)
#endif
            }
    }

    private func applyObservers<Content: View>(to view: Content) -> some View {
        let commands = applyCommandObservers(to: view)
        let gameState = applyGameStateObservers(to: commands)
        let interactions = applyInteractionObservers(to: gameState)
        return applyLifecycleObservers(to: interactions)
    }

    private func applyCommandObservers<Content: View>(to view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                isShowingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRulesAndScoring)) { _ in
                presentRulesAndScoring(initialSection: .rules)
            }
    }

    private func applyGameStateObservers<Content: View>(to view: Content) -> some View {
        view
            .onChange(of: gameVariantRawValue) { _, newValue in
                guard hasLoadedGame, !isHydratingGame else { return }
                let variant = GameVariant(rawValue: newValue) ?? .klondike
                stopAutoFinish()
                winCelebration.reset(to: .idle)
                isScreenshotSession = false
                viewModel.newGame(variant: variant, drawMode: drawMode)
                persistGameNow()
            }
            .onChange(of: drawModeRawValue) { (_, newValue: Int) in
                guard viewModel.supportsDrawMode else { return }
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
    }

    private func applyInteractionObservers<Content: View>(to view: Content) -> some View {
        view
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
    }

    private func applyLifecycleObservers<Content: View>(to view: Content) -> some View {
        view
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
#if os(macOS)
            .focusedSceneValue(\.gameMenuActions, gameMenuActions)
            .focusedSceneValue(\.gameMenuState, gameMenuState)
#endif
    }

    @ViewBuilder
    private func boardRoot(for geometry: GeometryProxy) -> some View {
        let presentation = boardPresentation(for: geometry)
        let surface = boardSurface(presentation: presentation)
        let preferences = applyBoardPreferences(to: surface)
        let geometryObserved = applyBoardGeometryObservers(to: preferences, geometry: geometry)
        let wasteObserved = applyWasteObservers(to: geometryObserved, presentation: presentation)
        applyBoardOverlays(to: wasteObserved, presentation: presentation)
    }

    private func boardPresentation(for geometry: GeometryProxy) -> BoardPresentation {
        let columnCount = max(viewModel.state.tableau.count, viewModel.gameVariant == .freecell ? 8 : 7)
#if os(iOS)
        let metrics = Layout.metrics(
            for: geometry.size,
            isRegularWidth: horizontalSizeClass == .regular,
            tableauColumnCount: columnCount
        )
#else
        let metrics = Layout.metrics(for: geometry.size, tableauColumnCount: columnCount)
#endif
        let cardSize = metrics.cardSize
        let contentWidth = (cardSize.width * CGFloat(columnCount))
            + (metrics.columnSpacing * CGFloat(max(0, columnCount - 1)))
        let scale = boardScaleFactor(
            availableWidth: geometry.size.width,
            requiredWidth: contentWidth + (metrics.horizontalPadding * 2)
        )
#if os(iOS)
        let centersContent = horizontalSizeClass == .regular && geometry.size.width > geometry.size.height
#else
        let centersContent = true
#endif
        return BoardPresentation(
            metrics: metrics,
            columnCount: columnCount,
            contentWidth: contentWidth,
            scale: scale,
            effectiveCardSize: CGSize(width: cardSize.width * scale, height: cardSize.height * scale),
            hintedTarget: viewModel.hintedDestination.map(dropTarget(for:)),
            centersContent: centersContent
        )
    }

    private func boardSurface(presentation: BoardPresentation) -> some View {
        ZStack {
            TableBackground()
            if hasLoadedGame && !isHydratingGame {
                boardLayout(presentation: presentation)
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
        .coordinateSpace(.named("board"))
        .sensoryFeedback(trigger: hapticFeedback.trigger) {
            hapticFeedback.feedbackForTrigger
        }
    }

    private func boardLayout(presentation: BoardPresentation) -> some View {
        VStack(alignment: .leading, spacing: presentation.metrics.rowSpacing) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let metrics = headerMetrics(at: context.date)
                headerView(
                    elapsedSeconds: metrics.elapsedSeconds,
                    score: metrics.score,
                    boardContentWidth: presentation.contentWidth,
                    onScoreTapped: { presentRulesAndScoring(initialSection: .scoring) }
                )
            }
            topRow(presentation: presentation)
            tableauRow(presentation: presentation)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(!isWinCascadeAnimating)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: presentation.centersContent ? .top : .topLeading
        )
        .padding(.horizontal, presentation.metrics.horizontalPadding)
        .padding(.vertical, presentation.metrics.verticalPadding)
        .scaleEffect(presentation.scale, anchor: .top)
    }

    private func topRow(presentation: BoardPresentation) -> some View {
        TopRowView(
            viewModel: viewModel,
            variant: viewModel.gameVariant,
            cardSize: presentation.metrics.cardSize,
            columnSpacing: presentation.metrics.columnSpacing,
            wasteFanSpacing: presentation.metrics.wasteFanSpacing,
            activeTarget: activeTarget,
            hintedTarget: presentation.hintedTarget,
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
        .frame(width: presentation.contentWidth, alignment: .leading)
    }

    private func tableauRow(presentation: BoardPresentation) -> some View {
        TableauRowView(
            viewModel: viewModel,
            cardSize: presentation.metrics.cardSize,
            columnSpacing: presentation.metrics.columnSpacing,
            faceDownOffset: presentation.metrics.tableauFaceDownOffset,
            faceUpOffset: presentation.metrics.tableauFaceUpOffset,
            maxPileHeight: presentation.metrics.tableauMaxHeight,
            activeTarget: activeTarget,
            hintedTarget: presentation.hintedTarget,
            hintHighlightOpacity: hintHighlightOpacity,
            isCardTiltEnabled: isCardTiltEnabled,
            cardTilts: $cardTilts,
            hiddenCardIDs: effectiveHiddenCardIDs,
            hintedCardIDs: viewModel.hintedCardIDs,
            hintWiggleToken: viewModel.hintWiggleToken,
            dragGesture: dragGesture(for:)
        )
        .frame(width: presentation.contentWidth, alignment: .leading)
    }

    private func applyBoardPreferences<Content: View>(to view: Content) -> some View {
        view
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
    }

    private func applyBoardGeometryObservers<Content: View>(
        to view: Content,
        geometry: GeometryProxy
    ) -> some View {
        view
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
    }

    private func applyWasteObservers<Content: View>(
        to view: Content,
        presentation: BoardPresentation
    ) -> some View {
        view
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
                    // The overlay cards fan themselves while flipping; the real
                    // cards wait fully fanned underneath.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        for card in newCards {
                            wasteFanProgress[card.id] = 1
                        }
                    }
                    startDrawAnimation(
                        for: newCards,
                        cardSize: presentation.effectiveCardSize,
                        fanSpacing: presentation.metrics.wasteFanSpacing * presentation.scale
                    )
                }
                previousWasteCount = newValue
                previousStockCount = stockCount
            }
    }

    private func applyBoardOverlays<Content: View>(
        to view: Content,
        presentation: BoardPresentation
    ) -> some View {
        view
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.state)
            .animation(.easeInOut(duration: 0.12), value: activeTarget)
            .overlay {
                GeometryReader { _ in
                    ZStack {
                        DrawOverlayView(
                            cards: drawAnimationCards,
                            cardSize: presentation.effectiveCardSize,
                            isCardTiltEnabled: isCardTiltEnabled,
                            cardTilts: $cardTilts
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

    private func headerMetrics(at date: Date) -> HeaderMetrics {
        if viewModel.isClockAdvancing {
            return HeaderMetrics(
                elapsedSeconds: viewModel.elapsedActiveSeconds(at: date),
                score: viewModel.displayScore(at: date)
            )
        }
        return HeaderMetrics(elapsedSeconds: viewModel.elapsedActiveSeconds(), score: viewModel.displayScore())
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

#if os(macOS)
    private var gameMenuActions: GameMenuActions {
        GameMenuActions(
            newGame: { startNewGameFromUI() },
            redeal: redealFromUI,
            undo: {
                stopAutoFinish()
                beginUndoAnimationIfNeeded()
            },
            autoFinish: {
                if isAutoFinishing {
                    stopAutoFinish()
                } else {
                    startAutoFinish()
                }
            },
            hint: triggerHint,
            showStatistics: { isShowingStats = true }
        )
    }

    private var gameMenuState: GameMenuState {
        GameMenuState(
            canUndo: !isUndoDisabled,
            canAutoFinish: isAutoFinishing || !isAutoFinishDisabled,
            canHint: !isHintDisabled,
            isHintVisible: isHintButtonVisible,
            isAutoFinishing: isAutoFinishing
        )
    }
#endif

    private func triggerHint() {
        guard !isHintDisabled else { return }
        stopAutoFinish()
        viewModel.requestHint()
    }

    private func startNewGameFromUI(variant: GameVariant? = nil) {
        stopAutoFinish()
        winCelebration.reset(to: .idle)
        isScreenshotSession = false
        let selectedVariant = variant ?? gameVariant
        viewModel.newGame(variant: selectedVariant, drawMode: drawMode)
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
        case .freeCell(let index):
            started = viewModel.startDragFromFreeCell(index: index)
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
            completeDropAnimation()
        }
    }

    private func completeDropAnimation() {
        for card in droppingSelection?.cards ?? [] {
            cardTilts.removeValue(forKey: card.id)
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let destination = pendingDropDestination {
                viewModel.handleDrop(to: destination)
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

    private func startDrawAnimation(for newCards: [Card], cardSize: CGSize, fanSpacing: CGFloat) {
        guard let plan = DrawAnimationCoordinator.makeDrawPlan(
            newCards: newCards,
            cardSize: cardSize,
            stockFrame: stockFrame,
            wasteFrame: wasteFrame,
            fanSpacing: fanSpacing
        ) else {
            return
        }

        drawAnimationCards = plan.cards
        drawingCardIDs = plan.cardIDs
        drawAnimationToken = plan.token

        DispatchQueue.main.asyncAfter(deadline: .now() + plan.travelDuration + plan.settleDuration) {
            guard drawAnimationToken == plan.token else { return }
            drawAnimationCards = []
            drawingCardIDs = []
        }
    }

    private func destination(for target: DropTarget) -> Destination {
        switch target {
        case .freeCell(let index):
            return .freeCell(index)
        case .foundation(let index):
            return .foundation(index)
        case .tableau(let index):
            return .tableau(index)
        }
    }

    private func dropTarget(for destination: Destination) -> DropTarget {
        switch destination {
        case .freeCell(let index):
            return .freeCell(index)
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

        let plan: UndoAnimationCoordinator.Plan = {
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

        guard !plan.items.isEmpty else {
            viewModel.undo()
            return
        }

        startUndoAnimation(with: plan)
    }

    private func startUndoAnimation(with plan: UndoAnimationCoordinator.Plan) {
        undoAnimationItems = plan.items
        undoAnimationTargets = plan.targets
        undoAnimationProgress = 0
        isUndoAnimating = true
        hiddenCardIDs = Set(plan.items.map(\.id))
        if plan.needsPostUndoFrames {
            cardFrames = [:]
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.undo()
        }

        if plan.needsPostUndoFrames {
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
    ) -> UndoAnimationCoordinator.Plan {
        UndoAnimationCoordinator.buildPlan(
            context: context,
            cards: UndoAnimationCoordinator.Cards(before: beforeCards, after: afterCards),
            frames: UndoAnimationCoordinator.Frames(
                cards: startingFrames,
                stock: stockFrame,
                waste: wasteFrame
            )
        )
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
            guard let target = undoAnimationTargets[item.id],
                  let endFrame = resolveUndoTargetFrame(target) else {
                return nil
            }
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
        for card in state.freeCells.compactMap({ $0 }) { lookup[card.id] = card }
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
        case freeCell(Int)
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
        for (index, card) in state.freeCells.enumerated() {
            if let card {
                locations[card.id] = .freeCell(index)
            }
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
    ) -> UndoAnimationCoordinator.Plan {
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

        return UndoAnimationCoordinator.Plan(
            items: items,
            targets: targets,
            needsPostUndoFrames: needsPostUndoFrames
        )
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
             (.some(.waste(_)), .some(.waste(_))),
             (.some(.freeCell(_)), .some(.freeCell(_))):
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

        if restoreScreenshotFixtureIfRequested() {
            // Staged board loaded; shared post-load setup below still applies.
        } else if let payload = GamePersistence.load(from: modelContext), viewModel.restore(from: payload) {
            if gameVariantRawValue != viewModel.gameVariant.rawValue {
                gameVariantRawValue = viewModel.gameVariant.rawValue
            }
            if viewModel.supportsDrawMode, drawModeRawValue != viewModel.stockDrawCount {
                drawModeRawValue = viewModel.stockDrawCount
            }
        } else {
            winCelebration.reset(to: .idle)
            viewModel.newGame(variant: gameVariant, drawMode: drawMode)
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

    /// Width overflow is computed analytically from the same inputs the board
    /// lays out with; vertical overflow is prevented by per-pile compression.
    private func boardScaleFactor(availableWidth: CGFloat, requiredWidth: CGFloat) -> CGFloat {
        guard requiredWidth > 0 else { return 1 }
        return min(1, availableWidth / requiredWidth)
    }

    private func restoreScreenshotFixtureIfRequested() -> Bool {
#if DEBUG
        guard let payload = ScreenshotFixtures.payloadFromLaunchArguments(),
              viewModel.restore(from: payload) else {
            return false
        }
        isScreenshotSession = true
        if gameVariantRawValue != viewModel.gameVariant.rawValue {
            gameVariantRawValue = viewModel.gameVariant.rawValue
        }
        if viewModel.supportsDrawMode, drawModeRawValue != viewModel.stockDrawCount {
            drawModeRawValue = viewModel.stockDrawCount
        }
        return true
#else
        return false
#endif
    }

    private func persistGameNow() {
        guard hasLoadedGame else { return }
        // A screenshot session must never overwrite the real saved game.
        guard !isScreenshotSession else { return }
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
