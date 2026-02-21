import SwiftUI

struct RulesAndScoringView: View {
    @Environment(\.dismiss) private var dismiss

    enum Section: String, CaseIterable, Identifiable {
        case rules = "Rules"
        case scoring = "Scoring"
        case terms = "Terms"

        var id: String { rawValue }
    }

    @State private var selectedSection: Section

    init(initialSection: Section = .rules) {
        _selectedSection = State(initialValue: initialSection)
    }

    private struct TermRow: Identifiable {
        let id = UUID()
        let term: String
        let definition: String
    }

    private struct ScoringRow: Identifiable {
        let id = UUID()
        let move: String
        let points: Int
        let note: String?
    }

    private let terms: [TermRow] = [
        TermRow(term: "Tableau", definition: "The seven play piles where you build down in alternating colors."),
        TermRow(term: "Foundations", definition: "Four suit piles built up from Ace to King."),
        TermRow(term: "Stock", definition: "The face-down draw pile."),
        TermRow(term: "Waste", definition: "Face-up cards drawn from the stock; only the top card is playable."),
        TermRow(term: "Draw mode", definition: "How many cards are drawn from stock each time: 1-card or 3-card.")
    ]

    private let scoringRows: [ScoringRow] = [
        ScoringRow(move: "Waste to Tableau", points: Scoring.delta(for: .wasteToTableau), note: nil),
        ScoringRow(move: "Waste to Foundation", points: Scoring.delta(for: .wasteToFoundation), note: nil),
        ScoringRow(move: "Tableau to Foundation", points: Scoring.delta(for: .tableauToFoundation), note: nil),
        ScoringRow(move: "Turn over Tableau card", points: Scoring.delta(for: .turnOverTableauCard), note: nil),
        ScoringRow(move: "Foundation to Tableau", points: Scoring.delta(for: .foundationToTableau), note: nil),
        ScoringRow(
            move: "Recycle waste in 1-card draw",
            points: Scoring.delta(for: .recycleWasteInDrawOne),
            note: nil
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 620, minHeight: 360)
        .navigationTitle("Rules & Scoring")
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

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
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

    private var termsCard: some View {
        sectionCard(title: "Terms") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(terms) { row in
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
        sectionCard(title: "Rules") {
            VStack(alignment: .leading, spacing: 8) {
                rulesRow("Build tableau piles down by alternating colors.")
                rulesRow("Move Aces to foundations first, then build each suit up to King.")
                rulesRow("Only Kings can fill an empty tableau pile.")
                rulesRow("In 1-card draw, flip one stock card at a time. In 3-card draw, flip three.")
                rulesRow("When stock is empty, recycle waste to stock and continue.")
                rulesRow("You win by moving all 52 cards to foundations.")
            }
        }
    }

    private var scoringCard: some View {
        sectionCard(title: "Scoring") {
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
                    ForEach(scoringRows) { row in
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
                Text("On win, a time bonus is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Time bonus starts at \(Scoring.timedMaxBonusDrawOne) in 1-card draw and \(Scoring.timedMaxBonusDrawThree) in 3-card draw, then drops by \(Scoring.timedPointsLostPerSecond) point per second.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Score cannot go below \(Scoring.minimumScore).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        RulesAndScoringView()
    }
}
