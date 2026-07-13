import Foundation
import SwiftUI
import SwiftData

/// Statistics in two levels, mirroring the game picker's grammar: an
/// overview of every game with aggregate highlights, and a per-game detail
/// with the full breakdown. Opens deep-linked to the current game's detail.
struct StatisticsView: View {
    let viewModel: SolitaireViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var path: [GameVariant]
    private let initialMode: GameMode

    init(viewModel: SolitaireViewModel?, initialMode: GameMode = .klondikeDrawThree) {
        self.viewModel = viewModel
        self.initialMode = initialMode
        _path = State(initialValue: [initialMode.variant])
    }

    var body: some View {
        NavigationStack(path: $path) {
            StatisticsOverviewView(
                viewModel: viewModel,
                onDone: { dismiss() }
            )
            .navigationDestination(for: GameVariant.self) { variant in
                GameStatisticsDetailView(
                    viewModel: viewModel,
                    variant: variant,
                    initialMode: initialMode,
                    onDone: { dismiss() }
                )
            }
        }
    }
}

// MARK: - Overview

/// Aggregate highlights plus one row per game — the two numbers that make
/// games comparable at a glance — in the shared presentation order.
private struct StatisticsOverviewView: View {
    let viewModel: SolitaireViewModel?
    let onDone: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var aggregate = GameStatistics()
    @State private var statsByVariant: [GameVariant: GameStatistics] = [:]
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    statsHighlightCard(
                        icon: "percent",
                        label: "Win Rate",
                        value: statsWinRateLabel(aggregate)
                    )
                    Divider()
                        .frame(height: 32)
                    statsHighlightCard(
                        icon: "number",
                        label: "Games Played",
                        value: "\(aggregate.gamesPlayed)"
                    )
                    Divider()
                        .frame(height: 32)
                    statsHighlightCard(
                        icon: "trophy.fill",
                        label: "Games Won",
                        value: "\(aggregate.gamesWon)"
                    )
                }
                .padding(.vertical, 2)
            } header: {
                Text("Highlights")
            }

            Section {
                ForEach(GameVariant.allCases, id: \.self) { variant in
                    NavigationLink(value: variant) {
                        gameRow(variant)
                    }
                }
            } header: {
                Text("Games")
            }

            Text("Tracked since \(statsTrackedSinceLabel(aggregate))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .navigationTitle("Statistics")
        .statisticsFormChrome()
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
                Button("Done", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            reload()
        }
        .confirmationDialog(
            "Reset all statistics?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Statistics", role: .destructive) {
                resetAllStatistics()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset statistics for every game.")
        }
    }

    private func gameRow(_ variant: GameVariant) -> some View {
        let stats = statsByVariant[variant] ?? GameStatistics()
        return HStack {
            Text(variant.title)
            Spacer(minLength: 16)
            if stats.gamesPlayed == 0 {
                Text("Not played yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(stats.gamesPlayed) played · \(statsWinRateLabel(stats)) won")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func reload() {
        statsByVariant = GameVariant.allCases.reduce(into: [:]) { result, variant in
            result[variant] = GameStatistics.aggregated(
                GameMode.modes(for: variant).map { GameStatisticsStore.load(for: $0) }
            )
        }
        aggregate = GameStatistics.aggregated(
            GameMode.allCases.map { GameStatisticsStore.load(for: $0) }
        )
    }

    private func resetAllStatistics() {
        for mode in GameMode.allCases {
            GameStatisticsStore.reset(for: mode)
        }
        // Stashed sessions must not finalize pre-reset play into the fresh
        // buckets; the active session is handled after so its newer in-memory
        // state wins the save slot.
        GamePersistence.invalidateStatisticsTracking(for: GameMode.allCases, in: modelContext)
        viewModel?.resetStatisticsTracking()
        persistTrackingReset(of: viewModel, in: modelContext)
        reload()
    }
}

// MARK: - Per-game detail

private struct GameStatisticsDetailView: View {
    let viewModel: SolitaireViewModel?
    let variant: GameVariant
    let onDone: () -> Void
    @Environment(\.modelContext) private var modelContext
    /// The bucket within a multi-mode game (Klondike draw counts, Spider
    /// suit counts); fixed for single-mode games.
    @State private var scopeMode: GameMode
    @State private var stats = GameStatistics()
    @State private var barHoverState: (label: String, x: CGFloat)?
    @State private var isShowingCleanWinsInfo = false
    @State private var isShowingResetConfirmation = false

    init(
        viewModel: SolitaireViewModel?,
        variant: GameVariant,
        initialMode: GameMode,
        onDone: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.variant = variant
        self.onDone = onDone
        _scopeMode = State(
            initialValue: initialMode.variant == variant ? initialMode : GameMode(variant: variant)
        )
    }

    private var effectiveMode: GameMode {
        let modes = GameMode.modes(for: variant)
        guard modes.count > 1 else { return modes.first ?? scopeMode }
        return modes.contains(scopeMode) ? scopeMode : GameMode(variant: variant)
    }

    private var effectiveScopeTitle: String {
        guard GameMode.modes(for: variant).count > 1 else { return variant.title }
        return "\(variant.title) (\(effectiveMode.optionTitle))"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Form {
                if GameMode.modes(for: variant).count > 1 {
                    Section {
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
                        statsHighlightCard(
                            icon: "percent",
                            label: "Win Rate",
                            value: statsWinRateLabel(stats)
                        )
                        Divider()
                            .frame(height: 32)
                        statsHighlightCard(
                            icon: "timer",
                            label: "Best Time",
                            value: bestTimeLabel
                        )
                        Divider()
                            .frame(height: 32)
                        statsHighlightCard(
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
                    statsKeyValueRow("Games Played", "\(stats.gamesPlayed)")
                    statsKeyValueRow("Wins", "\(stats.gamesWon)")
                    VStack(spacing: 6) {
                        statsKeyValueRow("Win Rate", statsWinRateLabel(stats))
                        if stats.gamesPlayed > 0 {
                            winLossBar
                        }
                    }
                    cleanWinsRow
                } header: {
                    Text("Games")
                }

                Section {
                    statsKeyValueRow("Total Time", statsDurationLabel(displayTotalTimeSeconds(at: context.date)))
                    statsKeyValueRow("Avg Time", statsDurationLabel(stats.averageTimeSeconds))
                    statsKeyValueRow("Best Time", bestTimeLabel)
                    if variant.lowerScoreIsBetter {
                        // Golf scores like its namesake: bests are lowest, and
                        // holes roll up into nine-hole matches.
                        statsKeyValueRow("Best Hole (lowest)", statsScoreLabel(stats.lowestScore))
                        statsKeyValueRow("Best Match (lowest)", statsScoreLabel(stats.bestMatchTotal))
                        statsKeyValueRow("Matches Completed", "\(stats.golfMatchesCompleted)")
                    } else {
                        statsKeyValueRow("High Score", statsScoreLabel(highScore(for: effectiveMode)))
                    }
                } header: {
                    Text("Performance")
                }

                Text("Tracked since \(statsTrackedSinceLabel(stats))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(variant.title)
        .statisticsFormChrome()
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
                Button("Done", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            loadStats()
        }
        .onChange(of: scopeMode) { _, _ in
            loadStats()
            barHoverState = nil
        }
        .confirmationDialog(
            "Reset \(effectiveScopeTitle) statistics?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset \(effectiveScopeTitle) Statistics", role: .destructive) {
                resetStatistics()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset only \(effectiveScopeTitle) games, times, win rates, and high scores.")
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

    private var bestTimeLabel: String {
        guard let bestTimeSeconds = stats.bestTimeSeconds else { return "-" }
        return statsDurationLabel(bestTimeSeconds)
    }

    /// Each mode bucket carries a single high score, routed to the field its
    /// wins record into (Klondike per draw count, Spider per suit count).
    /// Golf never records one — its stroke scores are lower-is-better and
    /// render through their own rows instead.
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
        case .freecell, .pyramid, .tripeaks, .yukon, .fortyThieves:
            return stats.highScore
        case .golf:
            return nil
        }
    }

    private var cleanWinRateLabel: String {
        String(format: "%.1f%%", stats.cleanWinRate * 100)
    }

    private func displayTotalTimeSeconds(at date: Date) -> Int {
        let liveElapsed: Int
        if activeModeMatchesScope {
            liveElapsed = viewModel?.unfinalizedElapsedSecondsForStats(at: date) ?? 0
        } else {
            liveElapsed = 0
        }
        let (sum, overflow) = stats.totalTimeSeconds.addingReportingOverflow(liveElapsed)
        return overflow ? Int.max : max(0, sum)
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

    private func resetStatistics() {
        GameStatisticsStore.reset(for: effectiveMode)
        // The mode's stashed session must not finalize pre-reset play into
        // the fresh bucket; an active session is handled after so its newer
        // in-memory state wins the save slot.
        GamePersistence.invalidateStatisticsTracking(for: [effectiveMode], in: modelContext)
        if activeModeMatchesScope {
            viewModel?.resetStatisticsTracking()
            persistTrackingReset(of: viewModel, in: modelContext)
        }
        loadStats()
        barHoverState = nil
    }

    private var activeModeMatchesScope: Bool {
        viewModel?.gameMode == effectiveMode
    }

    private func loadStats() {
        stats = GameStatisticsStore.load(for: effectiveMode)
    }
}

// MARK: - Shared pieces

private let statsDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = .dropLeading
    return formatter
}()

private func statsDurationLabel(_ seconds: Int) -> String {
    let total = max(0, seconds)
    return statsDurationFormatter.string(from: TimeInterval(total)) ?? "0s"
}

private func statsWinRateLabel(_ stats: GameStatistics) -> String {
    String(format: "%.1f%%", stats.winRate * 100)
}

private func statsScoreLabel(_ score: Int?) -> String {
    score.map { "\($0)" } ?? "-"
}

private func statsTrackedSinceLabel(_ stats: GameStatistics) -> String {
    guard let trackedSince = stats.trackedSince else { return "-" }
    return trackedSince.formatted(date: .abbreviated, time: .omitted)
}

private func statsHighlightCard(icon: String, label: String, value: String) -> some View {
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

private func statsKeyValueRow(_ key: String, _ value: String) -> some View {
    HStack {
        Text(key)
        Spacer(minLength: 16)
        Text(value)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

private func persistTrackingReset(of viewModel: SolitaireViewModel?, in modelContext: ModelContext) {
    guard let viewModel else { return }
    do {
        try GamePersistence.save(viewModel.persistencePayload(), in: modelContext)
    } catch {
#if DEBUG
        print("Failed to persist reset tracking state: \(error)")
#endif
    }
}

private extension View {
    /// Platform chrome every statistics page shares.
    func statisticsFormChrome() -> some View {
#if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
#else
        return formStyle(.grouped)
            .padding(16)
            .frame(minWidth: 420, minHeight: 320)
#endif
    }
}
