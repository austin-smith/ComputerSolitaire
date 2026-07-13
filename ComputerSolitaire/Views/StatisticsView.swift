import Foundation
import SwiftUI
import SwiftData

struct StatisticsView: View {
    let viewModel: SolitaireViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScope: Scope
    /// The bucket within a multi-mode scope (Klondike draw counts, Spider
    /// suit counts); ignored for single-mode scopes.
    @State private var scopeMode: GameMode
    @State private var stats = GameStatistics()
    @State private var barHoverState: (label: String, x: CGFloat)?
    @State private var isShowingCleanWinsInfo = false
    @State private var isShowingResetConfirmation = false
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()

    private enum Scope: String, CaseIterable, Identifiable {
        // Mirrors GameVariant's presentation order, with the aggregate last.
        case klondike
        case spider
        case freecell
        case tripeaks
        case pyramid
        case yukon
        case all

        var id: String { rawValue }

        init(variant: GameVariant) {
            switch variant {
            case .klondike:
                self = .klondike
            case .freecell:
                self = .freecell
            case .yukon:
                self = .yukon
            case .spider:
                self = .spider
            case .pyramid:
                self = .pyramid
            case .tripeaks:
                self = .tripeaks
            }
        }

        /// The variant this scope covers; nil for the aggregate scope.
        var variant: GameVariant? {
            switch self {
            case .klondike:
                return .klondike
            case .freecell:
                return .freecell
            case .yukon:
                return .yukon
            case .spider:
                return .spider
            case .pyramid:
                return .pyramid
            case .tripeaks:
                return .tripeaks
            case .all:
                return nil
            }
        }

        var title: String {
            switch self {
            case .klondike, .freecell, .yukon, .spider, .pyramid, .tripeaks:
                return variant?.title ?? ""
            case .all:
                return "All"
            }
        }
    }

    private struct HighScoreRow: Identifiable {
        let label: String
        let score: Int?

        var id: String { label }
    }

    init(viewModel: SolitaireViewModel?, initialMode: GameMode = .klondikeDrawThree) {
        self.viewModel = viewModel
        _selectedScope = State(initialValue: Scope(variant: initialMode.variant))
        _scopeMode = State(initialValue: initialMode)
    }

    /// The statistics bucket the current scope selection reads; nil for the
    /// aggregate scope.
    private var effectiveMode: GameMode? {
        guard let variant = selectedScope.variant else { return nil }
        let modes = GameMode.modes(for: variant)
        guard modes.count > 1 else { return modes.first }
        return modes.contains(scopeMode) ? scopeMode : GameMode(variant: variant)
    }

    private var effectiveScopeTitle: String {
        guard let variant = selectedScope.variant else { return "All" }
        guard GameMode.modes(for: variant).count > 1, let mode = effectiveMode else {
            return variant.title
        }
        return "\(variant.title) (\(mode.optionTitle))"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Form {
                Section {
                    Picker("Statistics Scope", selection: $selectedScope) {
                        ForEach(Scope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if let variant = selectedScope.variant, GameMode.modes(for: variant).count > 1 {
                        Picker("Game Mode", selection: $scopeMode) {
                            ForEach(GameMode.modes(for: variant), id: \.self) { mode in
                                Text(mode.optionTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                Section {
                    HStack(spacing: 0) {
                        highlightCard(
                            icon: "percent",
                            label: "Win Rate",
                            value: winRateLabel
                        )
                        Divider()
                            .frame(height: 32)
                        highlightCard(
                            icon: secondaryHighlightIcon,
                            label: secondaryHighlightLabel,
                            value: secondaryHighlightValue
                        )
                        Divider()
                            .frame(height: 32)
                        highlightCard(
                            icon: "trophy.fill",
                            label: "Games Won",
                            value: "\(stats.gamesWon)"
                        )
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Highlights")
                }

                Section {
                    keyValueRow("Games Played", "\(stats.gamesPlayed)")
                    keyValueRow("Wins", "\(stats.gamesWon)")
                    VStack(spacing: 6) {
                        keyValueRow("Win Rate", winRateLabel)
                        if stats.gamesPlayed > 0 {
                            winLossBar
                        }
                    }
                    cleanWinsRow
                } header: {
                    Text("Games")
                }

                if selectedScope != .all {
                    Section {
                        keyValueRow("Total Time", durationLabel(displayTotalTimeSeconds(at: context.date)))
                        keyValueRow("Avg Time", durationLabel(stats.averageTimeSeconds))
                        keyValueRow("Best Time", bestTimeLabel)
                        ForEach(highScoreRowsForSelectedScope) { row in
                            keyValueRow(row.label, scoreLabel(row.score))
                        }
                    } header: {
                        Text("Performance")
                    }
                }

                Text("Tracked since \(trackedSinceLabel)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("Statistics")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#else
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
#endif
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button("Reset Stats") {
                    isShowingResetConfirmation = true
                }
            }
#else
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset Stats") {
                    isShowingResetConfirmation = true
                }
            }
#endif
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            loadStats()
        }
        .onChange(of: selectedScope) { _, _ in
            if let variant = selectedScope.variant,
               !GameMode.modes(for: variant).contains(scopeMode) {
                scopeMode = GameMode(variant: variant)
            }
            loadStats()
            barHoverState = nil
        }
        .onChange(of: scopeMode) { _, _ in
            loadStats()
            barHoverState = nil
        }
        .confirmationDialog(
            resetDialogTitle,
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(resetActionTitle, role: .destructive) {
                resetStatistics()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetMessage)
        }
    }

    private var winLossBar: some View {
        let losses = stats.gamesPlayed - stats.gamesWon
        let winsLabel = "\(stats.gamesWon) \(stats.gamesWon == 1 ? "win" : "wins")"
        let lossesLabel = "\(losses) \(losses == 1 ? "loss" : "losses")"
        return GeometryReader { geo in
            let winFraction = CGFloat(stats.gamesWon) / CGFloat(max(1, stats.gamesPlayed))
            let winWidth = max(winFraction > 0 ? 4 : 0, geo.size.width * winFraction - 1)
            let lossWidth = max(winFraction < 1 ? 4 : 0, geo.size.width * (1 - winFraction) - 1)
            HStack(spacing: 2) {
                barSegment(fill: .green.opacity(0.6), width: winWidth, label: winsLabel, xOffset: 0)
                barSegment(fill: .red.opacity(0.35), width: lossWidth, label: lossesLabel, xOffset: winWidth + 2)
            }
            .overlay(alignment: .topLeading) {
                if let hover = barHoverState {
                    Text(hover.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .fixedSize()
                        .position(x: hover.x, y: -16)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 8)
        .padding(.top, 2)
    }

    private func barSegment(fill: some ShapeStyle, width: CGFloat, label: String, xOffset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(width: width)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    barHoverState = (label: label, x: xOffset + location.x)
                case .ended:
                    barHoverState = nil
                }
            }
    }

    private var winRateLabel: String {
        String(format: "%.1f%%", stats.winRate * 100)
    }

    private var bestTimeLabel: String {
        guard let bestTimeSeconds = stats.bestTimeSeconds else { return "-" }
        return durationLabel(bestTimeSeconds)
    }

    /// Each mode bucket carries a single high score, routed to the field its
    /// wins record into (Klondike per draw count, Spider per suit count).
    private var highScoreRowsForSelectedScope: [HighScoreRow] {
        guard let mode = effectiveMode else { return [] }
        return [HighScoreRow(label: "High Score", score: highScore(for: mode))]
    }

    private func highScore(for mode: GameMode) -> Int? {
        switch mode {
        case .klondikeDrawOne:
            return stats.highScoreDrawOne
        case .klondikeDrawThree:
            return stats.highScoreDrawThree
        case .spiderOneSuit:
            return stats.highScoreOneSuit
        case .spiderTwoSuits:
            return stats.highScoreTwoSuits
        case .spiderFourSuits:
            return stats.highScoreFourSuits
        case .freecell, .pyramid, .tripeaks, .yukon:
            return stats.highScore
        }
    }

    private func scoreLabel(_ score: Int?) -> String {
        score.map { "\($0)" } ?? "-"
    }

    private var secondaryHighlightIcon: String {
        if selectedScope == .all {
            return "number"
        }
        return "timer"
    }

    private var secondaryHighlightLabel: String {
        if selectedScope == .all {
            return "Games Played"
        }
        return "Best Time"
    }

    private var secondaryHighlightValue: String {
        if selectedScope == .all {
            return "\(stats.gamesPlayed)"
        }
        return bestTimeLabel
    }

    private var cleanWinRateLabel: String {
        return String(format: "%.1f%%", stats.cleanWinRate * 100)
    }

    private var trackedSinceLabel: String {
        guard let trackedSince = stats.trackedSince else { return "-" }
        return trackedSince.formatted(date: .abbreviated, time: .omitted)
    }

    private func displayTotalTimeSeconds(at date: Date) -> Int {
        let liveElapsed: Int
        if activeModeMatchesSelectedScope {
            liveElapsed = viewModel?.unfinalizedElapsedSecondsForStats(at: date) ?? 0
        } else {
            liveElapsed = 0
        }
        let (sum, overflow) = stats.totalTimeSeconds.addingReportingOverflow(liveElapsed)
        return overflow ? Int.max : max(0, sum)
    }

    private func highlightCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.headline, design: .monospaced, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var cleanWinsRow: some View {
        HStack(spacing: 4) {
            Text("Clean Wins")
            Button {
                isShowingCleanWinsInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clean Wins info")
            .popover(isPresented: $isShowingCleanWinsInfo, arrowEdge: .top) {
                Text("Wins completed without the use of hints, undos, or redeals.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280, alignment: .leading)
                    .padding(12)
#if os(iOS)
                    .presentationCompactAdaptation(.popover)
#endif
            }
            Spacer(minLength: 12)
            Text("\(stats.cleanWins) (\(cleanWinRateLabel))")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .padding(.leading, 2)
    }

    private func durationLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return durationFormatter.string(from: TimeInterval(total)) ?? "0s"
    }

    private func resetStatistics() {
        let affectedModes = effectiveMode.map { [$0] } ?? GameMode.allCases
        for mode in affectedModes {
            GameStatisticsStore.reset(for: mode)
        }

        // Stashed sessions of the affected modes must not finalize pre-reset
        // play into the fresh buckets; the active session is handled below so
        // its newer in-memory state wins the save slot.
        GamePersistence.invalidateStatisticsTracking(for: affectedModes, in: modelContext)

        if selectedScope == .all || activeModeMatchesSelectedScope {
            viewModel?.resetStatisticsTracking()
            persistTrackingResetIfNeeded()
        }
        loadStats()
        barHoverState = nil
    }

    private var activeModeMatchesSelectedScope: Bool {
        guard let mode = effectiveMode else { return true }
        return viewModel?.gameMode == mode
    }

    private var resetDialogTitle: String {
        selectedScope == .all
            ? "Reset all statistics?"
            : "Reset \(effectiveScopeTitle) statistics?"
    }

    private var resetActionTitle: String {
        selectedScope == .all
            ? "Reset All Statistics"
            : "Reset \(effectiveScopeTitle) Statistics"
    }

    private var resetMessage: String {
        selectedScope == .all
            ? "This will reset statistics for every game."
            : "This will reset only \(effectiveScopeTitle) games, times, win rates, and high scores."
    }

    private func loadStats() {
        if let mode = effectiveMode {
            stats = GameStatisticsStore.load(for: mode)
        } else {
            stats = GameStatistics.aggregated(
                GameMode.allCases.map { GameStatisticsStore.load(for: $0) }
            )
        }
    }

    private func persistTrackingResetIfNeeded() {
        guard let viewModel else { return }
        do {
            try GamePersistence.save(viewModel.persistencePayload(), in: modelContext)
        } catch {
#if DEBUG
            print("Failed to persist reset tracking state: \(error)")
#endif
        }
    }
}
