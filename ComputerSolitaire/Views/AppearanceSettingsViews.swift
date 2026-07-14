import Foundation
import SwiftUI

/// Front-face thumbnail of a card style, reused at chip size on the Cards
/// page and at row-icon size on the settings top level.
struct CardStylePreview: View {
    let style: CardStyle
    let cardSize: CGSize

    private var previewCard: Card {
        Card(suit: .hearts, rank: .queen, isFaceUp: true)
    }

    var body: some View {
        switch style {
        case .classic:
            ClassicCardFrontView(card: previewCard, cardSize: cardSize, isSelected: false)
        case .simple:
            SimpleCardFrontView(card: previewCard, cardSize: cardSize, isSelected: false)
        case .pixel:
            PixelCardFrontView(card: previewCard, cardSize: cardSize, isSelected: false)
        }
    }
}

// MARK: - Table

struct TableSettingsView: View {
    @AppStorage(SettingsKey.tableBackgroundColor)
    private var tableBackgroundColorRawValue = TableBackgroundColor.defaultValue.rawValue
    @AppStorage(SettingsKey.feltEffectEnabled) private var isFeltEffectEnabled = true

    var body: some View {
        Form {
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
            }
        }
        .navigationTitle("Table")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#else
        .formStyle(.grouped)
        .padding(16)
#endif
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
                            .accessibilityHidden(true)
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
}

// MARK: - Cards

struct CardsSettingsView: View {
    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.cardStyle) private var cardStyleRawValue = CardStyle.defaultValue.rawValue
    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(CardStyle.allCases) { style in
                        cardStyleChip(style)
                    }
                }
                .padding(.vertical, 4)
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
                Toggle(isOn: $isCardTiltEnabled) {
                    Text("Natural card tilt")
                    Text("Adds a subtle organic angle to each card.")
                }
                .toggleStyle(.switch)
            }
        }
        .navigationTitle("Cards")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#else
        .formStyle(.grouped)
        .padding(16)
#endif
        .onChange(of: cardStyleRawValue) { oldValue, newValue in
            guard oldValue != newValue else { return }
            HapticManager.shared.play(.settingsSelection)
        }
    }

    private func cardStyleChip(_ style: CardStyle) -> some View {
        let isSelected = cardStyleRawValue == style.rawValue

        return Button {
            guard !isSelected else { return }
            HapticManager.shared.play(.settingsSelection)
            withAnimation(.smooth(duration: 0.3)) {
                cardStyleRawValue = style.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                CardStylePreview(style: style, cardSize: CGSize(width: 44, height: 64))
                    .frame(width: 44, height: 64)

                VStack(spacing: 1) {
                    Text(style.title)
                        .font(.caption.weight(.bold))
                    Text(style.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .selectionChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
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
                            .accessibilityHidden(true)
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

#Preview("Table") {
    NavigationStack {
        TableSettingsView()
    }
}

#Preview("Cards") {
    NavigationStack {
        CardsSettingsView()
    }
}
