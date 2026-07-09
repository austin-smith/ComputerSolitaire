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
    static let tableBackgroundColor = "settings.tableBackgroundColor"
    static let feltEffectEnabled = "settings.feltEffectEnabled"
    static let soundEffectsEnabled = "settings.soundEffectsEnabled"
    static let showHintButton = "settings.showHintButton"
    static let cardStyle = "settings.cardStyle"
    static let cardBackColor = "settings.cardBackColor"
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
    @AppStorage(SettingsKey.cardStyle) private var cardStyleRawValue = CardStyle.default.rawValue
    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id
#if os(iOS)
    @State private var selectedAppIcon = AppIcon.current()
    @State private var isShowingAppIconPicker = false
#endif

    var body: some View {
        Form {
            tableSection
            cardsSection
            audioSection
            gameplaySection
            gameTypeSection

#if os(iOS)
            if UIApplication.shared.supportsAlternateIcons {
                appIconSection
            }
#endif

            helpSection
        }
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#else
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520, minHeight: 320)
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
#if os(iOS)
        .sheet(isPresented: $isShowingAppIconPicker) {
            NavigationStack {
                AppIconPickerView(selection: $selectedAppIcon)
            }
            .presentationDetents([.medium, .large])
        }
#endif
        .onChange(of: drawModeRawValue) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticManager.shared.play(.settingsSelection)
        }
        .onChange(of: gameVariantRawValue) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticManager.shared.play(.settingsSelection)
        }
        .onChange(of: cardStyleRawValue) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticManager.shared.play(.settingsSelection)
        }
    }

    // MARK: - Sections

    private var tableSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Background color")
                    Spacer()
                    if let selected = TableBackgroundColor(rawValue: tableBackgroundColorRawValue) {
                        Text(selected.label)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(TableBackgroundColor.allCases) { option in
                        colorSwatch(option)
                    }
                }
            }
            .padding(.vertical, 4)
            Toggle(isOn: $isFeltEffectEnabled) {
                Text("Felt texture")
                Text("Adds a fabric texture and vignette to the table.")
            }
            .toggleStyle(.switch)
        } header: {
            Text("Table")
        }
    }

    private var cardsSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(CardStyle.allCases) { style in
                    cardStyleCard(style)
                }
            }
            .padding(.vertical, 4)
            Toggle(isOn: $isCardTiltEnabled) {
                Text("Natural card tilt")
                Text("Adds a subtle organic angle to each card.")
            }
            .toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Card back color")
                    Spacer()
                    Text(CardBackColor.from(rawValue: cardBackColorRawValue).label)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(CardBackColor.all) { option in
                        cardBackSwatch(option)
                    }
                    Spacer()
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Cards")
        }
    }

    private var audioSection: some View {
        Section {
            Toggle(isOn: $isSoundEffectsEnabled) {
                Text("Sound effects")
                Text("Play card and game action sounds.")
            }
            .toggleStyle(.switch)
        } header: {
            Text("Audio")
        }
    }

    private var gameplaySection: some View {
        Section {
            Toggle(isOn: $isHintButtonVisible) {
                Text("Show hint button")
                Text("Turn off to avoid spoilers about hint availability.")
            }
            .toggleStyle(.switch)
        } header: {
            Text("Gameplay")
        }
    }

    private var gameTypeSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(GameVariant.allCases, id: \.rawValue) { variant in
                    variantCard(variant)
                }
            }
            .padding(.vertical, 4)

            if gameVariantRawValue == GameVariant.klondike.rawValue {
                Picker("Stock draw", selection: $drawModeRawValue) {
                    ForEach(DrawMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Game Type")
        }
    }

#if os(iOS)
    private var appIconSection: some View {
        Section {
            Button {
                isShowingAppIconPicker = true
            } label: {
                HStack(spacing: 10) {
                    AppIconPreviewView(icon: selectedAppIcon, size: 30)
                    Text(selectedAppIcon.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("App Icon")
        }
    }
#endif

    private var helpSection: some View {
        Section {
            Button {
                isShowingRulesAndScoring = true
            } label: {
                HStack {
                    Text("Rules & Scoring")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Help")
        }
    }

    // MARK: - Custom controls

    private func variantCard(_ variant: GameVariant) -> some View {
        Button {
            guard gameVariantRawValue != variant.rawValue else { return }
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
            .settingsChip(isSelected: gameVariantRawValue == variant.rawValue)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(gameVariantRawValue == variant.rawValue ? .isSelected : [])
    }

    private func cardStyleCard(_ style: CardStyle) -> some View {
        Button {
            guard cardStyleRawValue != style.rawValue else { return }
            HapticManager.shared.play(.settingsSelection)
            withAnimation(.smooth(duration: 0.3)) {
                cardStyleRawValue = style.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                cardStylePreview(style)
                    .frame(width: 44, height: 64)

                VStack(spacing: 1) {
                    Text(style.title)
                        .font(.caption.weight(.bold))
                    Text(style.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsChip(isSelected: cardStyleRawValue == style.rawValue)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(cardStyleRawValue == style.rawValue ? .isSelected : [])
    }

    @ViewBuilder
    private func cardStylePreview(_ style: CardStyle) -> some View {
        switch style {
        case .legacy:
            LegacyCardFrontView(
                card: Card(suit: .hearts, rank: .queen, isFaceUp: true),
                cardSize: CGSize(width: 44, height: 64),
                isSelected: false
            )
        case .pixel:
            PixelCardFrontView(
                card: Card(suit: .hearts, rank: .queen, isFaceUp: true),
                cardSize: CGSize(width: 44, height: 64),
                isSelected: false
            )
        case .default:
            DefaultCardFrontView(
                card: Card(suit: .hearts, rank: .queen, isFaceUp: true),
                cardSize: CGSize(width: 44, height: 64),
                isSelected: false
            )
        }
    }

    private func colorSwatch(_ option: TableBackgroundColor) -> some View {
        let isSelected = tableBackgroundColorRawValue == option.rawValue

        return Button {
            guard !isSelected else { return }
            HapticManager.shared.play(.settingsSelection)
            tableBackgroundColorRawValue = option.rawValue
        } label: {
            Circle()
                .fill(option.color)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.18),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cardBackSwatch(_ option: CardBackColor) -> some View {
        let isSelected = cardBackColorRawValue == option.id

        return Button {
            guard !isSelected else { return }
            HapticManager.shared.play(.settingsSelection)
            cardBackColorRawValue = option.id
        } label: {
            Circle()
                .fill(option.swatch)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.18),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func settingsChip(isSelected: Bool) -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .opacity(isSelected ? 1 : 0.75)
            .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
