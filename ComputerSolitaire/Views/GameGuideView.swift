import SwiftUI

struct GameGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.gameVariant) private var gameVariantRawValue = GameVariant.klondike.rawValue

    enum Section: String, CaseIterable, Identifiable {
        case rules = "Rules"
        case scoring = "Scoring"
        case terms = "Terms"

        var id: String { rawValue }
    }

    @State private var selectedSection: Section

    /// Hidden when the view is pushed onto a navigation stack rather than
    /// presented as its own sheet.
    private let showsDoneButton: Bool

    init(initialSection: Section = .rules, showsDoneButton: Bool = true) {
        _selectedSection = State(initialValue: initialSection)
        self.showsDoneButton = showsDoneButton
    }

    /// The variant being browsed. Defaults to the game in play, but the
    /// picker lets any game's rules be read from anywhere.
    @State private var selectedVariant: GameVariant?

    private var gameVariant: GameVariant {
        selectedVariant ?? GameVariant(rawValue: gameVariantRawValue) ?? .klondike
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text("Game")
                        .font(.subheadline.weight(.semibold))
                    Picker("Game", selection: browsedVariantSelection) {
                        ForEach(GameVariant.allCases, id: \.self) { variant in
                            Text(variant.title).tag(variant)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                Picker("Guide Section", selection: $selectedSection) {
                    ForEach(Section.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch selectedSection {
                case .rules:
                    rulesCard
                case .scoring:
                    scoringCard
                case .terms:
                    termsCard
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.vertical, contentVerticalPadding)
        }
#if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 620, minHeight: 360)
#else
        .frame(maxWidth: 620)
#endif
        .navigationTitle("Rules & Scoring")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private var browsedVariantSelection: Binding<GameVariant> {
        Binding(
            get: { gameVariant },
            set: { selectedVariant = $0 }
        )
    }

    private var contentHorizontalPadding: CGFloat {
#if os(iOS)
        return 30
#else
        return 24
#endif
    }

    private var contentVerticalPadding: CGFloat {
#if os(iOS)
        return 20
#else
        return 24
#endif
    }

    // The card deliberately has no heading of its own — the selected segment
    // above already names it.
    private func sectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
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

    private var termsCard: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(GameGuide.terms(for: gameVariant)) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.term)
                            .font(.subheadline.weight(.semibold))
                        Text(row.definition)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var rulesCard: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(GameGuide.rules(for: gameVariant), id: \.self) { rule in
                    rulesRow(rule)
                }
            }
        }
    }

    private var scoringCard: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Move")
                            .font(.subheadline.weight(.semibold))
                        Text("Points")
                            .font(.subheadline.weight(.semibold))
                    }
                    GridRow {
                        Divider().gridCellColumns(2)
                    }
                    ForEach(GameGuide.scoreRows(for: gameVariant)) { row in
                        GridRow(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.move)
                                if let note = row.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(pointsLabel(row.points))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                ForEach(GameGuide.scoringFootnotes(for: gameVariant), id: \.self) { footnote in
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rulesRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pointsLabel(_ points: Int) -> String {
        if points > 0 {
            return "+\(points)"
        }
        return "\(points)"
    }
}

#Preview {
    NavigationStack {
        GameGuideView()
    }
}
