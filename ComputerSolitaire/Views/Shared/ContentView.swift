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
    @State private var dealAnimationCards: [DrawAnimationCard] = []
    @State private var dealingCardIDs: Set<UUID> = []
    @State private var dealAnimationToken = UUID()
    /// The move count when the active deal flight took off; a later move means
    /// gameplay has mutated the position the flight refers to.
    @State private var dealAnimationMovesCount = 0
    @State private var undoAnimationItems: [UndoAnimationItem] = []
    @State private var undoAnimationTargets: [UUID: UndoAnimationEndTarget] = [:]
    @State private var undoAnimationProgress: CGFloat = 0
    @State private var isUndoAnimating = false
    @State private var hiddenCardIDs: Set<UUID> = []
    @State private var wasteFanProgress: [UUID: Double] = [:]
    @State private var boardViewportSize: CGSize = .zero
    @State private var headerHeight = HeaderView.estimatedHeight
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
    @State private var isShowingGamePicker = false
    @State private var rulesAndScoringInitialSection: RulesAndScoringView.Section = .rules
    @State private var isShowingStats = false
    @State private var timeScoringPauseReasons: Set<TimeScoringPauseReason> = []
    @State private var hintHighlightOpacity: Double = 0
    @State private var winCelebration = WinCelebrationController()

    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.gameVariant) private var gameVariantRawValue = GameVariant.klondike.rawValue
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue
    @AppStorage(SettingsKey.spiderSuitCount) private var spiderSuitCountRawValue = SpiderSuitCount.two.rawValue
    @AppStorage(SettingsKey.showHintButton) private var isHintButtonVisible = true
    @AppStorage(SettingsKey.cardStyle) private var cardStyleRawValue = CardStyle.defaultValue.rawValue
    @AppStorage(SettingsKey.tableBackgroundColor)
    private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue

    private var gameVariant: GameVariant {
        GameVariant(rawValue: gameVariantRawValue) ?? .klondike
    }

    private var drawMode: DrawMode {
        DrawMode(rawValue: drawModeRawValue) ?? .three
    }

    private var spiderSuitCount: SpiderSuitCount {
        SpiderSuitCount(rawValue: spiderSuitCountRawValue) ?? .two
    }

    private enum TimeScoringPauseReason: Hashable {
        case lifecycle
        case menuPresentation
        /// A dead Golf hole froze the clock: the hole's time is final the
        /// moment nothing plays, however long the completion overlay sits,
        /// and undoing out of the hole resumes without counting the dwell.
        case golfHoleOver
    }

    private var isAnyMenuPresented: Bool {
        isShowingSettings || isShowingRulesAndScoring || isShowingStats || isShowingGamePicker
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
            for: AnyView(
                GeometryReader { geometry in
                    boardRoot(for: geometry)
                }
                .environment(\.cardStyle, currentCardStyle)
            )
        )
        .accessibilityHidden(isShowingGamePicker)
        .overlay {
            if isShowingGamePicker {
                GameModePickerOverlay(
                    entries: gameModePickerEntries(),
                    currentMode: viewModel.gameMode,
                    feltColor: (TableBackgroundColor(rawValue: tableBackgroundColorRawValue)
                        ?? .defaultValue).color,
                    onSelect: { mode in
                        withAnimation(.smooth(duration: 0.25)) {
                            isShowingGamePicker = false
                        }
                        requestGameSwitch(to: mode)
                    },
                    onDismiss: {
                        withAnimation(.smooth(duration: 0.25)) {
                            isShowingGamePicker = false
                        }
                    }
                )
                .transition(.opacity)
            }
        }
    }

    private func sceneDecorations(for baseView: AnyView) -> some View {
        let toolbarView = applyToolbar(to: baseView)
        let sheetsView = applySheets(to: toolbarView)
        return applyObservers(to: sheetsView)
    }

    private func applyToolbar(to view: AnyView) -> AnyView {
        AnyView(
            view
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Section {
                            Button("New Game", systemImage: "plus") {
                                startNewGameFromUI()
                            }
                            Button("Redeal", systemImage: "arrow.clockwise") {
                                redealFromUI()
                            }
                            .disabled(!viewModel.canRedeal)
                        }
                        Section {
                            Button("Statistics", systemImage: "chart.bar") {
                                isShowingStats = true
                            }
                            Button("Rules & Scoring", systemImage: "book") {
                                presentRulesAndScoring(initialSection: .rules)
                            }
                        }
                        Section {
                            Button("Settings", systemImage: "gearshape") {
                                isShowingSettings = true
                            }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                if viewModel.isAutoFinishAvailable {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            startAutoFinish()
                        } label: {
                            // The bottom bar renders Labels icon-only.
                            HStack(spacing: 5) {
                                Image(systemName: "bolt")
                                Text("Auto")
                            }
                        }
                        .accessibilityLabel("Auto Finish")
                        .disabled(isAutoFinishDisabled)
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if isHintButtonVisible {
                        Button {
                            triggerHint()
                        } label: {
                            Label("Hint", systemImage: "lightbulb")
                        }
                        .disabled(isHintDisabled)
                    }
                    Button {
                        stopAutoFinish()
                        beginUndoAnimationIfNeeded()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(isUndoDisabled)
                }
#endif
#if os(macOS)
                ToolbarSpacer(.flexible)
                if viewModel.isAutoFinishAvailable {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            startAutoFinish()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt")
                                Text("Auto")
                            }
                        }
                        .accessibilityLabel("Auto Finish")
                        .help("Auto Finish")
                        .disabled(isAutoFinishDisabled)
                    }
                    ToolbarSpacer(.fixed)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        stopAutoFinish()
                        beginUndoAnimationIfNeeded()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .labelStyle(.iconOnly)
                    .help("Undo")
                    .disabled(isUndoDisabled)
                    if isHintButtonVisible {
                        Button {
                            triggerHint()
                        } label: {
                            Label("Hint", systemImage: "lightbulb")
                        }
                        .labelStyle(.iconOnly)
                        .help("Hint")
                        .disabled(isHintDisabled)
                    }
                }
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Game", systemImage: "plus") {
                            startNewGameFromUI()
                        }
                        Button("Redeal", systemImage: "arrow.clockwise") {
                            redealFromUI()
                        }
                        .disabled(!viewModel.canRedeal)
                    } label: {
                        Label("New Game", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .help("New Game or Redeal")
                }
                ToolbarSpacer(.fixed)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingStats = true
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                    .labelStyle(.iconOnly)
                    .help("Statistics")
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                    .help("Settings")
                }
#endif
            }
        )
    }

    private func gameModePickerEntries() -> [GameModePickerView.Entry] {
        GameMode.allCases.map { mode in
            GameModePickerView.Entry(mode: mode, isWon: gameModeIsWon(mode))
        }
    }

    /// The sub-game a variant's picker card opens: the live game's mode when
    /// the variant is active, else the last-played mode.
    private func defaultMode(for variant: GameVariant) -> GameMode {
        if viewModel.gameVariant == variant {
            return viewModel.gameMode
        }
        return GameMode(variant: variant, drawMode: drawMode, spiderSuitCount: spiderSuitCount)
    }

    private func gameModeIsWon(_ mode: GameMode) -> Bool {
        if mode == viewModel.gameMode {
            return viewModel.isWin
        }
        return GamePersistence.load(mode: mode, from: modelContext)?.state.isWon ?? false
    }

    /// UI entry point for switching games. Performs the switch and keeps the
    /// AppStorage selection in sync.
    private func requestGameSwitch(to mode: GameMode) {
        guard mode != viewModel.gameMode else { return }
        hapticFeedback.play(.settingsSelection)
        switchGame(to: mode)
    }

    private func applySheets(to view: AnyView) -> AnyView {
        AnyView(
            view.sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                }
#if os(macOS)
                .frame(minWidth: 420, idealWidth: 480, maxWidth: 520, minHeight: 380)
#endif
            }
            .sheet(isPresented: $isShowingRulesAndScoring) {
                NavigationStack {
                    RulesAndScoringView(initialSection: rulesAndScoringInitialSection)
                }
            }
            .sheet(isPresented: $isShowingStats) {
                // StatisticsView owns its NavigationStack: it drills from the
                // all-games overview into per-game detail on both platforms.
                StatisticsView(viewModel: viewModel, initialMode: viewModel.gameMode)
            }
        )
    }

    private func applyObservers(to view: AnyView) -> AnyView {
        let commandObservedView = AnyView(
            view
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                isShowingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRulesAndScoring)) { _ in
                presentRulesAndScoring(initialSection: .rules)
            }
        )

        let gameStateObservedView = AnyView(
            commandObservedView
            .onChange(of: gameVariantRawValue) { _, newValue in
                guard hasLoadedGame, !isHydratingGame else { return }
                let variant = GameVariant(rawValue: newValue) ?? .klondike
                guard variant != viewModel.gameVariant else { return }
                switchGame(to: defaultMode(for: variant))
            }
            .onChange(of: spiderSuitCountRawValue) { _, newValue in
                guard hasLoadedGame, !isHydratingGame else { return }
                guard viewModel.gameVariant == .spider else { return }
                let suitCount = SpiderSuitCount(rawValue: newValue) ?? .two
                guard suitCount != viewModel.state.spiderSuitCount else { return }
                switchGame(to: GameMode(variant: .spider, spiderSuitCount: suitCount))
            }
            .onChange(of: isAnyMenuPresented) { _, _ in
                updateMenuPresentationPauseState()
            }
            .onChange(of: viewModel.state) { _, _ in
                scheduleAutosave()
                queueAutoFinishStepIfPossible()
                // Every path into or out of a dead Golf hole is a state
                // change: the killing move freezes the clock, undo thaws it.
                updateGolfHoleOverPauseState()
            }
            .onChange(of: viewModel.movesCount) { _, _ in
                scheduleAutosave()
            }
            .onChange(of: viewModel.stockDrawCount) { _, _ in
                scheduleAutosave()
            }
            .onChange(of: viewModel.golfMatch) { _, _ in
                // Finishing the ninth hole mutates only the match — the board
                // stays as it was won or died — so the scorecard needs its own
                // autosave trigger to survive a relaunch at the summary.
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
        )

        return AnyView(
            gameStateObservedView
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
        )
    }

    @ViewBuilder
    private func boardRoot(for geometry: GeometryProxy) -> some View {
        let boardColumnCount = max(viewModel.state.tableau.count, viewModel.gameVariant.boardColumnCount)
#if os(iOS)
        let metrics = Layout.metrics(
            for: geometry.size,
            isRegularWidth: horizontalSizeClass == .regular,
            tableauColumnCount: boardColumnCount,
            headerHeight: headerHeight
        )
#else
        let metrics = Layout.metrics(
            for: geometry.size,
            tableauColumnCount: boardColumnCount,
            headerHeight: headerHeight
        )
#endif
        let cardSize = metrics.cardSize
        let boardContentWidth = (cardSize.width * CGFloat(boardColumnCount))
            + (metrics.columnSpacing * CGFloat(max(0, boardColumnCount - 1)))
        let boardScaleFactor = boardScaleFactor(
            availableWidth: geometry.size.width,
            requiredWidth: boardContentWidth + (metrics.horizontalPadding * 2)
        )
        let effectiveCardSize = CGSize(
            width: cardSize.width * boardScaleFactor,
            height: cardSize.height * boardScaleFactor
        )
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
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            guard abs(newHeight - headerHeight) >= 0.5 else { return }
                            headerHeight = newHeight
                        }
                    }
                    TopRowView(
                        viewModel: viewModel,
                        variant: viewModel.gameVariant,
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
                    if viewModel.gameVariant == .pyramid {
                        PyramidBoardView(
                            viewModel: viewModel,
                            cardSize: cardSize,
                            columnSpacing: metrics.columnSpacing,
                            maxBoardHeight: metrics.tableauMaxHeight,
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
                    } else if viewModel.gameVariant == .tripeaks {
                        TriPeaksBoardView(
                            viewModel: viewModel,
                            cardSize: cardSize,
                            columnSpacing: metrics.columnSpacing,
                            maxBoardHeight: metrics.tableauMaxHeight,
                            isCardTiltEnabled: isCardTiltEnabled,
                            cardTilts: $cardTilts,
                            hiddenCardIDs: effectiveHiddenCardIDs,
                            hintedCardIDs: viewModel.hintedCardIDs,
                            hintWiggleToken: viewModel.hintWiggleToken,
                            dragGesture: dragGesture(for:)
                        )
                        .frame(width: boardContentWidth, alignment: .leading)
                    } else if viewModel.gameVariant == .canfield {
                        CanfieldBoardRowView(
                            viewModel: viewModel,
                            cardSize: cardSize,
                            columnSpacing: metrics.columnSpacing,
                            faceDownOffset: metrics.tableauFaceDownOffset,
                            faceUpOffset: metrics.tableauFaceUpOffset,
                            maxPileHeight: metrics.tableauMaxHeight,
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
                    } else {
                        TableauRowView(
                            viewModel: viewModel,
                            cardSize: cardSize,
                            columnSpacing: metrics.columnSpacing,
                            faceDownOffset: metrics.tableauFaceDownOffset,
                            faceUpOffset: metrics.tableauFaceUpOffset,
                            maxPileHeight: metrics.tableauMaxHeight,
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
                    }
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
                HapticManager.shared.play(.gameWon)
                winCelebration.beginIfNeededForWin(
                    launchPiles: winCascadeLaunchPiles,
                    launchTargets: winCascadeLaunchTargets,
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
                    cardSize: effectiveCardSize,
                    fanSpacing: metrics.wasteFanSpacing * boardScaleFactor
                )
            }
            previousWasteCount = newValue
            previousStockCount = stockCount
        }
        .onChange(of: viewModel.latestTableauDealEvent) { _, event in
            // The tableau-deal variants send stock cards straight onto piles —
            // no waste change for the draw animation to key on. The session
            // publishes each deal as an explicit event (never set by restores,
            // undos, or game switches), so a hydrated game whose last move was
            // a deal can never replay the flight.
            guard let event else { return }
            startDealAnimation(for: event.dealtCardIDs)
        }
        .onChange(of: viewModel.movesCount) { _, movesCount in
            // The board stays live during a deal flight, and a move that lands
            // mid-flight can relocate a card the overlay is still flying toward
            // (a Scorpion group move carries an in-flight card away with the
            // cards beneath it). Land the flight rather than finish it against
            // a stale frame — the same rule the undo path applies. The deal's
            // own move is exempt: its count is the baseline taken at takeoff.
            guard movesCount != dealAnimationMovesCount else { return }
            guard !dealingCardIDs.isEmpty || !dealAnimationCards.isEmpty else { return }
            cancelDealAnimation()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.state)
        .animation(.easeInOut(duration: 0.12), value: activeTarget)
        .overlay {
            GeometryReader { _ in
                ZStack {
                    DrawOverlayView(
                        cards: drawAnimationCards,
                        cardSize: effectiveCardSize,
                        isCardTiltEnabled: isCardTiltEnabled,
                        cardTilts: $cardTilts
                    )
                    .zIndex(50)
                    DrawOverlayView(
                        cards: dealAnimationCards,
                        cardSize: effectiveCardSize,
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
                }
            }
            // Hidden deliberately: these are animation ghosts of on-board
            // cards. The interactive end-of-game overlays live in their own
            // layer below so VoiceOver can reach their controls.
            .accessibilityHidden(true)
        }
        .overlay {
            if viewModel.gameVariant == .golf {
                // Golf ends every hole through the match flow, so the
                // shared win overlay never presents for it.
                if viewModel.golfMatch.isComplete {
                    GolfMatchSummaryOverlay(match: viewModel.golfMatch) {
                        viewModel.startNewGolfMatch()
                    }
                    .transition(.opacity)
                } else if viewModel.isGolfHoleOver,
                          // A dead hole presents immediately; a won hole waits
                          // for the celebration to start, the same gate the
                          // shared win overlay uses.
                          !viewModel.isWin || winCelebration.phase != .idle {
                    GolfHoleCompleteOverlay(
                        holeNumber: viewModel.golfMatch.currentHoleNumber,
                        holeScore: viewModel.score,
                        matchTotalThroughHole: viewModel.golfLiveMatchTotal,
                        isFinalHole: viewModel.golfMatch.currentHoleNumber == GolfMatchState.holeCount,
                        didClearBoard: viewModel.isWin,
                        onAdvance: { viewModel.advanceGolfHole() },
                        onUndo: { viewModel.undo() }
                    )
                    .transition(.opacity)
                }
            } else if viewModel.isWin && winCelebration.phase != .idle {
                WinOverlay(score: viewModel.score) {
                    startNewGameFromUI()
                }
                .transition(.opacity)
            }
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
        let isGolf = viewModel.gameVariant == .golf
        return HeaderView(
            gameTitle: viewModel.gameVariant.title,
            gameQualifier: viewModel.gameMode.qualifier,
            movesCount: viewModel.movesCount,
            elapsedSeconds: elapsedSeconds,
            score: score,
            golfHoleLabel: isGolf
                ? "Hole \(viewModel.golfMatch.currentHoleNumber)/\(GolfMatchState.holeCount)"
                : nil,
            golfMatchTotal: isGolf ? viewModel.golfLiveMatchTotal : nil,
            onGameTitleTapped: {
                withAnimation(.smooth(duration: 0.25)) {
                    isShowingGamePicker = true
                }
            },
            onScoreTapped: onScoreTapped
        )
        .frame(width: boardContentWidth, alignment: .leading)
    }

    private var effectiveHiddenCardIDs: Set<UUID> {
        hiddenCardIDs
            .union(winCelebration.hiddenFoundationCardIDs)
            .union(dealingCardIDs)
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
            switchVariant: { requestGameSwitch(to: defaultMode(for: $0)) },
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
            currentVariant: gameVariant,
            canUndo: !isUndoDisabled,
            canRedeal: viewModel.canRedeal,
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

    private func startNewGameFromUI() {
        stopAutoFinish()
        winCelebration.reset(to: .idle)
        // New Game replaces the board as thoroughly as a game switch: stale
        // flights (deal, draw, undo) must not animate over the fresh deal.
        resetTransientBoardState()
        isScreenshotSession = false
        viewModel.newGame()
        persistGameNow()
    }

    /// Syncs the stored game selection (variant plus per-variant configuration)
    /// to the game now in play, so relaunches and picker defaults follow it.
    private func rememberSelectedGame() {
        if gameVariantRawValue != viewModel.gameVariant.rawValue {
            gameVariantRawValue = viewModel.gameVariant.rawValue
        }
        if viewModel.supportsDrawMode, drawModeRawValue != viewModel.stockDrawCount {
            drawModeRawValue = viewModel.stockDrawCount
        }
        if let suitCount = viewModel.state.spiderSuitCount,
           spiderSuitCountRawValue != suitCount.rawValue {
            spiderSuitCountRawValue = suitCount.rawValue
        }
    }

    private func redealFromUI() {
        guard viewModel.canRedeal else { return }
        stopAutoFinish()
        winCelebration.reset(to: .idle)
        // Redeal replaces the board like New Game does; see above.
        resetTransientBoardState()
        viewModel.redeal()
        persistGameNow()
    }

    /// Stashes the current game into its own save slot, then resumes the target
    /// game's stashed session (or deals fresh). Never records statistics —
    /// switching games is not abandoning a game.
    private func switchGame(to mode: GameMode) {
        // Stash before any teardown: if persistence fails, the switch is
        // abandoned and the live session keeps playing with nothing lost.
        guard persistGameNow() else { return }
        stopAutoFinish()
        winCelebration.reset(to: .idle)
        resetTransientBoardState()
        isHydratingGame = true
        isScreenshotSession = false
        let payload = GamePersistence.load(mode: mode, from: modelContext)
        viewModel.activateGame(mode, restoringFrom: payload)
        rememberSelectedGame()
        reconcileTimeScoringPause()
        winCelebration.syncForLoadedGame(
            launchPiles: winCascadeLaunchPiles,
            launchTargets: winCascadeLaunchTargets,
            isWin: viewModel.isWin,
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize
        )
        previousWasteCount = viewModel.state.waste.count
        previousStockCount = viewModel.state.stock.count
        isHydratingGame = false
        persistGameNow()
    }

    /// Clears in-flight drag/drop/undo/draw animation state so stale animation
    /// completions cannot mutate the game that replaces the current one.
    private func resetTransientBoardState() {
        activeTarget = nil
        dragTranslation = .zero
        dragReturnOffset = .zero
        isReturningDrag = false
        returningCards = []
        isDroppingCards = false
        droppingSelection = nil
        dropAnimationOffset = .zero
        pendingDropDestination = nil
        wasteReturnAnchorCardID = nil
        wasteReturnAnchorFrame = nil
        drawAnimationCards = []
        drawingCardIDs = []
        drawAnimationToken = UUID()
        cancelDealAnimation()
        undoAnimationItems = []
        undoAnimationTargets = [:]
        undoAnimationProgress = 0
        isUndoAnimating = false
        hiddenCardIDs = []
        wasteFanProgress = [:]
        hintHighlightOpacity = 0
    }

    private func startAutoFinish() {
        guard !isAutoFinishDisabled else { return }
        HapticManager.shared.play(.autoFinishStart)
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
        case .pyramid(let index):
            started = viewModel.startDragFromPyramid(index: index)
        case .triPeaks(let index):
            started = viewModel.startDragFromTriPeaks(index: index)
        case .reserve:
            started = viewModel.startDragFromReserve()
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

    /// Flies a stock-onto-tableau deal (Spider, Scorpion). The session records
    /// the dealt IDs in stock order and `removeLast()` deals, so the reversed
    /// order is pile order — leftmost pile's card takes off first. The real
    /// cards hide immediately (in the same update as the deal, so they never
    /// pop in) while their landing frames publish; the overlay then flies.
    private func startDealAnimation(for dealtCardIDs: [UUID]) {
        // Deals serialize: a rapid follow-up supersedes any active flight.
        // Clearing first is glitch-free — the superseded flight's cards are
        // real-rendered the moment they unhide — and keeps a failed follow-up
        // plan from stranding the prior overlay (its cleanup is token-gated).
        cancelDealAnimation()
        let lookup = cardLookup(in: viewModel.state)
        let dealtCards = dealtCardIDs.reversed().compactMap { lookup[$0] }
        guard !dealtCards.isEmpty, stockFrame != .zero else { return }

        dealingCardIDs = Set(dealtCards.map(\.id))
        dealAnimationMovesCount = viewModel.movesCount
        let token = UUID()
        dealAnimationToken = token
        DispatchQueue.main.async {
            resolveDealAnimation(for: dealtCards, token: token, attemptsRemaining: 24)
        }
    }

    private func cancelDealAnimation() {
        dealAnimationCards = []
        dealingCardIDs = []
        dealAnimationToken = UUID()
    }

    private func resolveDealAnimation(for dealtCards: [Card], token: UUID, attemptsRemaining: Int) {
        guard dealAnimationToken == token else { return }
        // Only cards still on the tableau ever publish a landing frame: a
        // dealt card that completed a run banked on arrival, and its run pile
        // publishes the run's top card only. Waiting on a banked card would
        // burn every retry before the plan — which already skips frame-less
        // cards — could run.
        let tableauCardIDs = Set(viewModel.state.tableau.joined().map(\.id))
        let awaitedCards = dealtCards.filter { tableauCardIDs.contains($0.id) }
        let framesReady = awaitedCards.allSatisfy { cardFrames[$0.id] != nil }
        if !framesReady, attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                resolveDealAnimation(for: dealtCards, token: token, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        guard let plan = DealAnimationCoordinator.makeDealPlan(
            dealtCards: dealtCards,
            cardFrames: cardFrames,
            stockFrame: stockFrame
        ) else {
            cancelDealAnimation()
            return
        }

        dealAnimationCards = plan.cards
        // The plan drops cards without a landing frame (banked on arrival);
        // trimming the hidden set to the flying cards un-hides those.
        dealingCardIDs = plan.cardIDs

        let total = plan.maxDelay + plan.travelDuration + plan.settleDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            guard dealAnimationToken == token else { return }
            dealAnimationCards = []
            dealingCardIDs = []
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
        case .pyramid(let index):
            return .pyramid(index)
        case .waste:
            return .waste
        case .discard:
            return .discard
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
        case .pyramid(let index):
            return .pyramid(index)
        case .waste:
            return .waste
        case .discard:
            return .discard
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
        // Undo mutates the position a live deal flight refers to; land the
        // flight before its reverse begins so the two never run concurrently.
        cancelDealAnimation()

        let currentFrames = cardFrames
        let beforeState = viewModel.state
        let beforeCards = cardLookup(in: beforeState)
        let afterCards = cardLookup(in: snapshot.state)

        if snapshot.undoContext?.action == .flipTableauTop {
            viewModel.undo()
            return
        }

        let (startingItems, targets, needsPostUndoFrames): (
            [UndoAnimationItem],
            [UUID: UndoAnimationEndTarget],
            Bool
        ) = {
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
            guard let target = undoAnimationTargets[item.id],
                  let endFrame = resolveUndoTargetFrame(target) else { return nil }
            return UndoAnimationItem(
                id: item.id,
                card: item.card,
                endFaceUp: item.endFaceUp,
                startFrame: item.startFrame,
                endFrame: endFrame
            )
        }

        let hasMovement = resolvedItems.contains { item in
            !framesApproximatelyEqual(item.startFrame, item.endFrame)
        }

        if !resolvedItems.isEmpty, hasMovement {
            undoAnimationItems = resolvedItems
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                undoAnimationProgress = 1
            }
            // One turn later — once the overlay views exist with their takeoff
            // faces — hand each card its post-undo face. CardView animates the
            // change, so a card returning to the stock turns face down in the
            // air instead of snapping on landing.
            DispatchQueue.main.async {
                guard isUndoAnimating else { return }
                undoAnimationItems = undoAnimationItems.map { item in
                    var flownCard = item.card
                    flownCard.isFaceUp = item.endFaceUp
                    return UndoAnimationItem(
                        id: item.id,
                        card: flownCard,
                        endFaceUp: item.endFaceUp,
                        startFrame: item.startFrame,
                        endFrame: item.endFrame
                    )
                }
            }
            // Slightly past the flight spring AND the mid-air flip (which
            // starts a turn late and runs 0.32s) so neither gets clipped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
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
        for card in state.pyramid.compactMap({ $0 }) { lookup[card.id] = card }
        for card in state.discard { lookup[card.id] = card }
        for card in state.triPeaks.compactMap({ $0 }) { lookup[card.id] = card }
        return lookup
    }

    private enum CardLocation: Equatable {
        case stock(Int)
        case waste(Int)
        case freeCell(Int)
        case foundation(pile: Int, index: Int)
        case tableau(pile: Int, index: Int)
        case pyramid(Int)
        case discard(Int)
        case triPeaks(Int)
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
        for (index, card) in state.pyramid.enumerated() {
            if let card {
                locations[card.id] = .pyramid(index)
            }
        }
        for (index, card) in state.discard.enumerated() {
            locations[card.id] = .discard(index)
        }
        for (index, card) in state.triPeaks.enumerated() {
            if let card {
                locations[card.id] = .triPeaks(index)
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
                    endFaceUp: (afterCards[id] ?? card).isFaceUp,
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

        let migratedCurrentMode = GamePersistence.migrateLegacyRecordsIfNeeded(in: modelContext)
        // The pooled-bucket splits assign history to the mode in active use.
        // The migrated game's own qualifier is the freshest signal for its
        // family (stored settings can lag the payload); the other family
        // still splits by its stored setting.
        GameStatisticsStore.migrateLegacyKlondikeStatisticsIfNeeded(
            activeDrawMode: migratedCurrentMode?.drawMode ?? drawMode
        )
        GameStatisticsStore.migrateLegacySpiderStatisticsIfNeeded(
            activeSuitCount: migratedCurrentMode?.spiderSuitCount ?? spiderSuitCount
        )

        // The stored selection decides which game's slot the app opens into —
        // except right after upgrading, when the game migrated out of the
        // legacy single slot was the one on screen and wins over stored
        // settings, which can lag its payload by one debounced autosave.
        // `rememberSelectedGame()` re-syncs the stored selection on restore.
        let launchMode = migratedCurrentMode ?? GameMode(
            variant: gameVariant,
            drawMode: drawMode,
            spiderSuitCount: spiderSuitCount
        )
        if restoreScreenshotFixtureIfRequested() {
            // Staged board loaded; shared post-load setup below still applies.
        } else if let payload = GamePersistence.load(mode: launchMode, from: modelContext),
                  viewModel.restore(from: payload) {
            rememberSelectedGame()
        } else {
            winCelebration.reset(to: .idle)
            viewModel.newGame(mode: launchMode)
            rememberSelectedGame()
            persistGameNow()
        }
        winCelebration.syncForLoadedGame(
            launchPiles: winCascadeLaunchPiles,
            launchTargets: winCascadeLaunchTargets,
            isWin: viewModel.isWin,
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize
        )

        reconcileTimeScoringPause()
    }

    /// Rebuilds the pause-reason set from the current scene and menu state
    /// and applies it to the session, resuming as well as pausing: a restored
    /// payload can carry a pause from stash time that no present reason
    /// justifies, and it must not stay frozen.
    private func reconcileTimeScoringPause() {
        timeScoringPauseReasons = []
        if shouldPauseForLifecycle {
            timeScoringPauseReasons.insert(.lifecycle)
        }
        if isAnyMenuPresented {
            timeScoringPauseReasons.insert(.menuPresentation)
        }
        if viewModel.isGolfHoleDead {
            timeScoringPauseReasons.insert(.golfHoleOver)
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
            launchPiles: winCascadeLaunchPiles,
            launchTargets: winCascadeLaunchTargets,
            isWin: true,
            dropFrames: dropFrames,
            boardViewportSize: boardViewportSize
        )
    }

    /// The cascade erupts from the foundations, except in Pyramid where every
    /// removed card lives on the discard, and in TriPeaks and Golf where every
    /// played card lives on the waste.
    private var winCascadeLaunchPiles: [[Card]] {
        switch viewModel.gameVariant {
        case .pyramid:
            return [viewModel.state.discard]
        case .tripeaks, .golf:
            return [viewModel.state.waste]
        case .klondike, .freecell, .yukon, .spider, .fortyThieves, .scorpion, .canfield:
            return viewModel.state.foundations
        }
    }

    private var winCascadeLaunchTargets: [DropTarget] {
        switch viewModel.gameVariant {
        case .pyramid:
            return [.discard]
        case .tripeaks, .golf:
            return [.waste]
        case .klondike, .freecell, .yukon, .spider, .fortyThieves, .scorpion, .canfield:
            return viewModel.state.foundations.indices.map(DropTarget.foundation)
        }
    }

    private func syncLifecyclePauseState() {
        updatePauseReason(.lifecycle, shouldPause: shouldPauseForLifecycle)
    }

    private func updateMenuPresentationPauseState() {
        updatePauseReason(.menuPresentation, shouldPause: isAnyMenuPresented)
    }

    private func updateGolfHoleOverPauseState() {
        updatePauseReason(.golfHoleOver, shouldPause: viewModel.isGolfHoleDead)
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
        rememberSelectedGame()
        return true
#else
        return false
#endif
    }

    /// Returns whether the session is safely on disk — true also when no
    /// save was required (nothing loaded yet, or a screenshot board that
    /// must never overwrite the real one).
    @discardableResult
    private func persistGameNow() -> Bool {
        guard hasLoadedGame else { return true }
        // A screenshot session must never overwrite the real saved game.
        guard !isScreenshotSession else { return true }
        autosaveTask?.cancel()
        autosaveTask = nil
        do {
            try GamePersistence.save(viewModel.persistencePayload(), in: modelContext)
            return true
        } catch {
#if DEBUG
            print("Failed to persist game state: \(error)")
#endif
            return false
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
