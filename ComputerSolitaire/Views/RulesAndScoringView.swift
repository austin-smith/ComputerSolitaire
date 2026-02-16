import SwiftUI

struct RulesAndScoringView: View {
    @Environment(\.dismiss) private var dismiss

    private struct ScoringRow: Identifiable {
        let id = UUID()
        let move: String
        let points: Int
        let note: String?
    }

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
                        Text("Score cannot go below \(Scoring.minimumScore).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
