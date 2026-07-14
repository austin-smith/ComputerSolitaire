import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    static let spiderSuitCount = "settings.spiderSuitCount"
    static let tableBackgroundColor = "settings.tableBackgroundColor"
    static let feltEffectEnabled = "settings.feltEffectEnabled"
    static let soundEffectsEnabled = "settings.soundEffectsEnabled"
    static let hapticFeedbackEnabled = "settings.hapticFeedbackEnabled"
    static let showHintButton = "settings.showHintButton"
    static let showGameStats = "settings.showGameStats"
    static let showStockCount = "settings.showStockCount"
    static let cardStyle = "settings.cardStyle"
    static let cardBackColor = "settings.cardBackColor"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.soundEffectsEnabled) private var isSoundEffectsEnabled = true
    @AppStorage(SettingsKey.hapticFeedbackEnabled) private var isHapticFeedbackEnabled = true
    @AppStorage(SettingsKey.showHintButton) private var isHintButtonVisible = true
    @AppStorage(SettingsKey.showGameStats) private var isGameStatsVisible = true
    @AppStorage(SettingsKey.showStockCount) private var isStockCountVisible = true
    @AppStorage(SettingsKey.tableBackgroundColor)
    private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue
    @AppStorage(SettingsKey.cardStyle) private var cardStyleRawValue = CardStyle.defaultValue.rawValue
#if os(iOS)
    @State private var selectedAppIcon = AppIcon.current()
#endif

    var body: some View {
        Form {
            appearanceSection
            soundAndHapticsSection
            gameplaySection
            helpSection
            aboutSection
        }
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#else
        .formStyle(.grouped)
        .padding(16)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// Title on the left, the current selection shown as a trailing preview —
    /// the preview itself is the value, no restating it in text.
    private func appearanceRow(
        title: String,
        value: String,
        @ViewBuilder preview: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            preview()
                .frame(width: 24, height: 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(value)
    }

    private var selectedTableColor: TableBackgroundColor {
        TableBackgroundColor(rawValue: tableBackgroundColorRawValue) ?? .defaultValue
    }

    private var selectedCardStyle: CardStyle {
        CardStyle(rawValue: cardStyleRawValue) ?? .defaultValue
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                TableSettingsView()
            } label: {
                appearanceRow(title: "Table", value: selectedTableColor.label) {
                    Circle()
                        .fill(selectedTableColor.color)
                        .overlay {
                            Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        }
                        .frame(width: 22, height: 22)
                }
            }
            NavigationLink {
                CardsSettingsView()
            } label: {
                appearanceRow(title: "Cards", value: selectedCardStyle.title) {
                    // Rendered at the chip size the card art is tuned for,
                    // then scaled down; tiny layout sizes distort the art.
                    CardStylePreview(
                        style: selectedCardStyle,
                        cardSize: CGSize(width: 44, height: 64)
                    )
                    .frame(width: 44, height: 64)
                    .scaleEffect(24.0 / 64.0)
                    .frame(width: 17, height: 24)
                }
            }
#if os(iOS)
            if UIApplication.shared.supportsAlternateIcons {
                NavigationLink {
                    AppIconPickerView(selection: $selectedAppIcon)
                } label: {
                    appearanceRow(title: "App Icon", value: selectedAppIcon.name) {
                        AppIconPreviewView(icon: selectedAppIcon, size: 24)
                    }
                }
            }
#endif
        } header: {
            Text("Appearance")
        }
    }

    private var soundAndHapticsSection: some View {
        Section {
            Toggle("Sound effects", isOn: $isSoundEffectsEnabled)
                .toggleStyle(.switch)
#if os(iOS)
            Toggle("Haptic feedback", isOn: $isHapticFeedbackEnabled)
                .toggleStyle(.switch)
#endif
        } header: {
#if os(iOS)
            Text("Sound & Haptics")
#else
            Text("Sound")
#endif
        }
    }

    private var gameplaySection: some View {
        Section {
            Toggle(isOn: $isGameStatsVisible) {
                Text("Show game stats")
                Text("Display moves, time, and score above the board.")
            }
            .toggleStyle(.switch)
            Toggle(isOn: $isStockCountVisible) {
                Text("Show stock count")
                Text("Display how many cards remain in the stock.")
            }
            .toggleStyle(.switch)
            Toggle(isOn: $isHintButtonVisible) {
                Text("Show hint button")
                Text("Turn off to avoid spoilers about hint availability.")
            }
            .toggleStyle(.switch)
        } header: {
            Text("Gameplay")
        }
    }

    private var helpSection: some View {
        Section {
            NavigationLink("Rules & Scoring") {
                RulesAndScoringView(showsDoneButton: false)
            }
        } header: {
            Text("Help")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                HStack {
                    Text("Computer Solitaire")
                    Spacer()
                    Text(AppInfo.version)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("About")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
