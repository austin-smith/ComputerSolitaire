import Foundation
import SwiftUI
import SwiftData

struct StatisticsView: View {
    let viewModel: SolitaireViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScope: Scope
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
        case klondike
        case freecell
        case yukon
        case spider
        case pyramid
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
            case .all:
                return nil
            }
        }

        var title: String {
            switch self {
            case .klondike, .freecell, .yukon, .spider, .pyramid:
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

    init(viewModel: SolitaireViewModel?, initialVariant: GameVariant = .klondike) {
        self.viewModel = viewModel
        _selectedScope = State(initialValue: Scope(variant: initialVariant))
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

    /// Klondike splits its high score by draw mode and Spider by suit count
    /// (scores across game modes aren't comparable); the other variants keep a
    /// single high score.
    private var highScoreRowsForSelectedScope: [HighScoreRow] {
        switch selectedScope {
        case .klondike:
            return [
                HighScoreRow(label: "High Score (3-card)", score: stats.highScoreDrawThree),
                HighScoreRow(label: "High Score (1-card)", score: stats.highScoreDrawOne)
            ]
        case .freecell, .yukon, .pyramid:
            return [HighScoreRow(label: "High Score", score: stats.highScore)]
        case .spider:
            return [
                HighScoreRow(label: "High Score (1 Suit)", score: stats.highScoreOneSuit),
                HighScoreRow(label: "High Score (2 Suits)", score: stats.highScoreTwoSuits),
                HighScoreRow(label: "High Score (4 Suits)", score: stats.highScoreFourSuits)
            ]
        case .all:
            return []
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
        if activeVariantMatchesSelectedScope {
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
        if let variant = selectedScope.variant {
            GameStatisticsStore.reset(for: variant)
        } else {
            for variant in GameVariant.allCases {
                GameStatisticsStore.reset(for: variant)
            }
        }

        if selectedScope == .all || activeVariantMatchesSelectedScope {
            viewModel?.resetStatisticsTracking()
            persistTrackingResetIfNeeded()
        }
        loadStats()
        barHoverState = nil
    }

    private var activeVariantMatchesSelectedScope: Bool {
        guard let variant = selectedScope.variant else { return true }
        return viewModel?.gameVariant == variant
    }

    private var resetDialogTitle: String {
        switch selectedScope {
        case .klondike:
            return "Reset Klondike statistics?"
        case .freecell:
            return "Reset FreeCell statistics?"
        case .yukon:
            return "Reset Yukon statistics?"
        case .spider:
            return "Reset Spider statistics?"
        case .pyramid:
            return "Reset Pyramid statistics?"
        case .all:
            return "Reset all statistics?"
        }
    }

    private var resetActionTitle: String {
        switch selectedScope {
        case .klondike:
            return "Reset Klondike Statistics"
        case .freecell:
            return "Reset FreeCell Statistics"
        case .yukon:
            return "Reset Yukon Statistics"
        case .spider:
            return "Reset Spider Statistics"
        case .pyramid:
            return "Reset Pyramid Statistics"
        case .all:
            return "Reset All Statistics"
        }
    }

    private var resetMessage: String {
        switch selectedScope {
        case .klondike:
            return "This will reset only Klondike games, times, win rates, and high scores."
        case .freecell:
            return "This will reset only FreeCell games, times, win rates, and high scores."
        case .yukon:
            return "This will reset only Yukon games, times, win rates, and high scores."
        case .spider:
            return "This will reset only Spider games, times, win rates, and high scores."
        case .pyramid:
            return "This will reset only Pyramid games, times, win rates, and high scores."
        case .all:
            return "This will reset Klondike, FreeCell, Yukon, Spider, and Pyramid statistics."
        }
    }

    private func loadStats() {
        if let variant = selectedScope.variant {
            stats = GameStatisticsStore.load(for: variant)
        } else {
            stats = GameStatistics.aggregated(
                GameVariant.allCases.map { GameStatisticsStore.load(for: $0) }
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
