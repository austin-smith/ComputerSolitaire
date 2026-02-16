import Foundation
import SwiftUI

enum TableBackgroundColor: String, CaseIterable, Identifiable {
    case ocean = "#0671b7"
    case blush = "#f8b7cd"
    case sky = "#67a3d9"
    case rose = "#fdd0e0"
    case ice = "#c8e7f5"
    case deepTeal = "#345b5b"
    case teal = "#5b9a9a"
    case seafoam = "#a8cccc"

    static let defaultValue: TableBackgroundColor = .teal

    var id: String { rawValue }

    var label: String {
        rawValue.uppercased()
    }

    var color: Color {
        switch self {
        case .ocean:
            return Color(red: 0.0235, green: 0.4431, blue: 0.7176)
        case .blush:
            return Color(red: 0.9725, green: 0.7176, blue: 0.8039)
        case .sky:
            return Color(red: 0.4039, green: 0.6392, blue: 0.851)
        case .rose:
            return Color(red: 0.9922, green: 0.8157, blue: 0.8784)
        case .ice:
            return Color(red: 0.7843, green: 0.9059, blue: 0.9608)
        case .deepTeal:
            return Color(red: 0.2039, green: 0.3569, blue: 0.3569)
        case .teal:
            return Color(red: 0.3569, green: 0.6039, blue: 0.6039)
        case .seafoam:
            return Color(red: 0.6588, green: 0.8, blue: 0.8)
        }
    }
}

enum SettingsKey {
    static let cardTiltEnabled = "settings.cardTiltEnabled"
    static let drawMode = "settings.drawMode"
    static let tableBackgroundColor = "settings.tableBackgroundColor"
    static let feltEffectEnabled = "settings.feltEffectEnabled"
    static let soundEffectsEnabled = "settings.soundEffectsEnabled"
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openRulesAndScoring = Notification.Name("openRulesAndScoring")
    static let openStatistics = Notification.Name("openStatistics")
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRulesAndScoring = false
    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue
    @AppStorage(SettingsKey.tableBackgroundColor) private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue
    @AppStorage(SettingsKey.feltEffectEnabled) private var isFeltEffectEnabled = true
    @AppStorage(SettingsKey.soundEffectsEnabled) private var isSoundEffectsEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: "Table") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Background color")
                            .font(.subheadline.weight(.semibold))
                        VStack(spacing: 8) {
                            ForEach(TableBackgroundColor.allCases) { option in
                                backgroundColorRow(option)
                            }
                        }
                        Toggle(isOn: $isFeltEffectEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Felt texture")
                                    .font(.subheadline.weight(.semibold))
                                Text("Adds a fabric texture and vignette to the table.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                SettingsCard(title: "Cards") {
                    Toggle(isOn: $isCardTiltEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Natural card tilt")
                                .font(.subheadline.weight(.semibold))
                            Text("Adds a subtle organic angle to each card.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                SettingsCard(title: "Audio") {
                    Toggle(isOn: $isSoundEffectsEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sound effects")
                                .font(.subheadline.weight(.semibold))
                            Text("Play card and game action sounds.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                SettingsCard(title: "Draw Mode") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stock draw")
                            .font(.subheadline.weight(.semibold))
                        Picker("Stock draw", selection: $drawModeRawValue) {
                            ForEach(DrawMode.allCases, id: \.rawValue) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text("Choose how many cards to draw from the stock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(title: "Help") {
                    Button {
                        isShowingRulesAndScoring = true
                    } label: {
                        HStack {
                            Text("Rules & Scoring")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520, minHeight: 260)
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .sheet(isPresented: $isShowingRulesAndScoring) {
            NavigationStack {
                RulesAndScoringView()
            }
        }
    }

    private func backgroundColorRow(_ option: TableBackgroundColor) -> some View {
        let isSelected = tableBackgroundColorRawValue == option.rawValue

        return Button {
            tableBackgroundColorRawValue = option.rawValue
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(option.color)
                    .frame(width: 36, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                Text(option.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stats = GameStatistics()

    var body: some View {
        Group {
#if os(iOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    gameStatsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
#else
            VStack(alignment: .leading, spacing: 16) {
                Text("Statistics")
                    .font(.title3.weight(.semibold))
                gameStatsCard
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
            .frame(minWidth: 460, idealWidth: 500, maxWidth: 560, minHeight: 380)
            .navigationTitle("Statistics")
#endif
        }
        .onAppear {
            stats = GameStatisticsStore.load()
        }
    }

    private var gameStatsCard: some View {
        StatsCard(title: "Game Stats") {
            VStack(spacing: 0) {
                statRow("Games Played", value: "\(stats.gamesPlayed)")
                rowDivider
                statRow("Games Won", value: "\(stats.gamesWon)")
                rowDivider
                statRow("Win Rate", value: winRateLabel)
                rowDivider
                statRow("Total Time", value: durationLabel(stats.totalTimeSeconds))
                rowDivider
                statRow("Avg Time", value: durationLabel(stats.averageTimeSeconds))
                rowDivider
                statRow("Best Time", value: bestTimeLabel)
                rowDivider
                statRow("High Score (3-card)", value: "\(stats.highScoreDrawThree)")
                rowDivider
                statRow("High Score (1-card)", value: "\(stats.highScoreDrawOne)")
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

    private var rowDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
            .padding(.vertical, 2)
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private func durationLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}

struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    SettingsView()
}
