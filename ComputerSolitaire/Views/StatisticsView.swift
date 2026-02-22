import Foundation
import SwiftUI

struct StatisticsView: View {
    let viewModel: SolitaireViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var stats = GameStatistics()
    @State private var barHoverState: (label: String, x: CGFloat)?
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Form {
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
                            icon: "timer",
                            label: "Best Time",
                            value: bestTimeLabel
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

                Section("Games") {
                    keyValueRow("Games Played", "\(stats.gamesPlayed)")
                    keyValueRow("Games Won", "\(stats.gamesWon)")
                    VStack(spacing: 6) {
                        keyValueRow("Win Rate", winRateLabel)
                        if stats.gamesPlayed > 0 {
                            winLossBar
                        }
                    }
                }

                Section("Performance") {
                    keyValueRow("Total Time", durationLabel(displayTotalTimeSeconds(at: context.date)))
                    keyValueRow("Avg Time", durationLabel(stats.averageTimeSeconds))
                    keyValueRow("Best Time", bestTimeLabel)
                    keyValueRow("High Score (3-card)", "\(stats.highScoreDrawThree)")
                    keyValueRow("High Score (1-card)", "\(stats.highScoreDrawOne)")
                }
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            stats = GameStatisticsStore.load()
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
        .padding(.top, 4)
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

    private func displayTotalTimeSeconds(at date: Date) -> Int {
        let liveElapsed = viewModel?.unfinalizedElapsedSecondsForStats(at: date) ?? 0
        let (sum, overflow) = stats.totalTimeSeconds.addingReportingOverflow(liveElapsed)
        return overflow ? Int.max : max(0, sum)
    }

    private func highlightCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private func durationLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return durationFormatter.string(from: TimeInterval(total)) ?? "0s"
    }
}
