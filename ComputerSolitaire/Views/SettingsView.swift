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
    static let gameVariant = "settings.gameVariant"
    static let drawMode = "settings.drawMode"
    static let tableBackgroundColor = "settings.tableBackgroundColor"
    static let feltEffectEnabled = "settings.feltEffectEnabled"
    static let soundEffectsEnabled = "settings.soundEffectsEnabled"
    static let showHintButton = "settings.showHintButton"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRulesAndScoring = false
    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.gameVariant) private var gameVariantRawValue = GameVariant.klondike.rawValue
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue
    @AppStorage(SettingsKey.tableBackgroundColor) private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue
    @AppStorage(SettingsKey.feltEffectEnabled) private var isFeltEffectEnabled = true
    @AppStorage(SettingsKey.soundEffectsEnabled) private var isSoundEffectsEnabled = true
    @AppStorage(SettingsKey.showHintButton) private var isHintButtonVisible = true

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

                SettingsCard(title: "Gameplay") {
                    Toggle(isOn: $isHintButtonVisible) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show hint button")
                                .font(.subheadline.weight(.semibold))
                            Text("Hide hint controls to avoid spoilers about hint availability.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Game Type")
                        .font(.headline)
                        .padding(.leading, 4)

                    HStack(spacing: 12) {
                        ForEach(GameVariant.allCases, id: \.rawValue) { variant in
                            variantCard(variant)
                        }
                    }
                }

                if gameVariantRawValue == GameVariant.klondike.rawValue {
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
        .onChange(of: drawModeRawValue) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticManager.shared.play(.settingsSelection)
        }
        .onChange(of: gameVariantRawValue) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticManager.shared.play(.settingsSelection)
        }
    }

    private func variantCard(_ variant: GameVariant) -> some View {
        let isSelected = gameVariantRawValue == variant.rawValue

        return Button {
            guard !isSelected else { return }
            HapticManager.shared.play(.settingsSelection)
            withAnimation(.smooth(duration: 0.3)) {
                gameVariantRawValue = variant.rawValue
            }
        } label: {
            VStack(spacing: 3) {
                Text(variant.title)
                    .font(.subheadline.weight(.bold))

                Text(variant.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? .thickMaterial : .thinMaterial)
                    .shadow(
                        color: .black.opacity(isSelected ? 0.12 : 0.04),
                        radius: isSelected ? 8 : 2,
                        y: isSelected ? 4 : 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(isSelected ? 1 : 0),
                        lineWidth: 2.5
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.primary.opacity(isSelected ? 0 : 0.1),
                        lineWidth: 1
                    )
            }
            .opacity(isSelected ? 1 : 0.7)
            .scaleEffect(isSelected ? 1.0 : 0.96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func backgroundColorRow(_ option: TableBackgroundColor) -> some View {
        let isSelected = tableBackgroundColorRawValue == option.rawValue

        return Button {
            guard !isSelected else { return }
            HapticManager.shared.play(.settingsSelection)
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

#Preview {
    SettingsView()
}
