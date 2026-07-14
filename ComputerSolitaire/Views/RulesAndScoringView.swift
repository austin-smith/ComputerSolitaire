import SwiftUI

struct RulesAndScoringView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.gameVariant) private var gameVariantRawValue = GameVariant.klondike.rawValue

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
        TermRow(term: "Waste", definition: "Face-up cards drawn from the stock — only the top card is playable."),
        TermRow(term: "Draw mode", definition: "How many cards you draw from the stock at a time: 1-card or 3-card.")
    ]

    private var gameVariant: GameVariant {
        GameVariant(rawValue: gameVariantRawValue) ?? .klondike
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
                ForEach(termsForCurrentVariant) { row in
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
                ForEach(rulesForCurrentVariant, id: \.self) { rule in
                    rulesRow(rule)
                }
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
                    ForEach(scoringRowsForCurrentVariant) { row in
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
                if gameVariant.lowerScoreIsBetter {
                    Text(
                        "Golf scores run like golf: lower is better, there is no time bonus, "
                            + "and negative hole scores are possible after clearing the board."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("When you win, a time bonus is added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        "Time bonus starts at \(Scoring.timedMaxBonusDrawOne) in 1-card draw and "
                            + "\(Scoring.timedMaxBonusDrawThree) in 3-card draw, then drops by "
                            + "\(Scoring.timedPointsLostPerSecond) point per second."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Score cannot go below \(Scoring.minimumScore).")
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

    private var termsForCurrentVariant: [TermRow] {
        switch gameVariant {
        case .klondike:
            return terms
        case .freecell:
            return [
                TermRow(term: "Cascade", definition: "One of eight tableau columns where all cards are face up."),
                TermRow(term: "Free Cell", definition: "A temporary single-card holding slot (four total)."),
                TermRow(term: "Foundations", definition: "Four suit piles built up from Ace to King."),
                TermRow(
                    term: "Supermove",
                    definition: "A multi-card move made possible by open free cells and empty cascades."
                )
            ]
        case .yukon:
            return [
                TermRow(term: "Tableau", definition: "The seven play piles where you build down in alternating colors."),
                TermRow(term: "Foundations", definition: "Four suit piles built up from Ace to King."),
                TermRow(
                    term: "Group move",
                    definition: "Any face-up card together with every card stacked on top of it, moved as one, even out of order."
                )
            ]
        case .spider:
            return [
                TermRow(term: "Tableau", definition: "The ten play piles where you build down, regardless of suit."),
                TermRow(
                    term: "Run",
                    definition: "Face-up cards of one suit in descending order — only runs move together."
                ),
                TermRow(
                    term: "Completed run",
                    definition: "A full King-to-Ace run of one suit. It leaves the tableau automatically — eight complete the game."
                ),
                TermRow(term: "Stock", definition: "The face-down pile that deals one card onto every tableau pile at once."),
                TermRow(term: "Suits", definition: "The difficulty setting: the two decks are made of 1, 2, or 4 suits, always 104 cards.")
            ]
        case .pyramid:
            return [
                TermRow(
                    term: "Pyramid",
                    definition: "Twenty-eight face-up cards in seven overlapping rows — a card is exposed once both cards covering it are gone."
                ),
                TermRow(term: "Stock", definition: "The face-down draw pile."),
                TermRow(term: "Waste", definition: "Face-up cards drawn from the stock — only the top card is playable."),
                TermRow(term: "Discard", definition: "Where removed pairs and Kings go — cards there are out of play."),
                TermRow(
                    term: "Recycle",
                    definition: "Turning the waste back into the stock. Pyramid allows two recycles (three passes)."
                )
            ]
        case .tripeaks:
            return [
                TermRow(
                    term: "Peaks",
                    definition: "Twenty-eight cards in three overlapping peaks — a card is uncovered once both cards covering it are gone, and flips face up."
                ),
                TermRow(term: "Stock", definition: "The face-down draw pile. You get one pass through it — no recycles."),
                TermRow(
                    term: "Waste",
                    definition: "The growing face-up pile — play any uncovered card one rank above or below its top."
                ),
                TermRow(
                    term: "Chain",
                    definition: "Consecutive discards without flipping the stock — each discard in a chain is worth one more point than the last."
                )
            ]
        case .golf:
            return [
                TermRow(
                    term: "Columns",
                    definition: "Seven face-up piles of five cards — only each column's exposed card may play."
                ),
                TermRow(term: "Stock", definition: "The face-down draw pile. You get one pass through it — no recycles."),
                TermRow(
                    term: "Waste",
                    definition: "The growing face-up pile — play any exposed card one rank above or below its top."
                ),
                TermRow(term: "Hole", definition: "One deal. Nine holes make a match."),
                TermRow(
                    term: "Par",
                    definition: "45 strokes for a nine-hole match. Like golf, lower is better."
                )
            ]
        case .fortyThieves:
            return [
                TermRow(
                    term: "Tableau",
                    definition: "Ten columns of four face-up cards — build down by suit, one card at a time."
                ),
                TermRow(
                    term: "Foundations",
                    definition: "Eight suit piles built up from Ace to King, two per suit. Cards placed here never return to play."
                ),
                TermRow(term: "Stock", definition: "The face-down draw pile. You get one pass through it — no recycles."),
                TermRow(
                    term: "Waste",
                    definition: "Face-up cards drawn from the stock — only the top card is playable."
                )
            ]
        case .canfield:
            return [
                TermRow(
                    term: "Reserve",
                    definition: "Thirteen face-down cards with the top one face up and playable. Its top card automatically fills any empty tableau pile."
                ),
                TermRow(
                    term: "Base card",
                    definition: "The card dealt to the first foundation — its rank starts all four foundations."
                ),
                TermRow(
                    term: "Tableau",
                    definition: "Four piles built down in alternating colors, wrapping from Ace to King. Piles move only as a whole."
                ),
                TermRow(
                    term: "Foundations",
                    definition: "Four suit piles built up from the base rank, wrapping from King to Ace. Cards placed here never return to play."
                ),
                TermRow(term: "Stock", definition: "The face-down draw pile. Three cards turn over at a time, with unlimited redeals."),
                TermRow(term: "Waste", definition: "Face-up cards drawn from the stock — only the top card is playable.")
            ]
        case .scorpion:
            return [
                TermRow(term: "Tableau", definition: "The seven play piles where you build down by suit."),
                TermRow(
                    term: "Group move",
                    definition: "Any face-up card together with every card stacked on top of it, moved as one, even out of order."
                ),
                TermRow(
                    term: "Completed run",
                    definition: "A full King-to-Ace run of one suit. It leaves the tableau automatically — four complete the game."
                ),
                TermRow(
                    term: "Stock",
                    definition: "Three face-down cards, dealt face up onto the first three piles at any time — but only once."
                )
            ]
        }
    }

    private var rulesForCurrentVariant: [String] {
        switch gameVariant {
        case .klondike:
            return [
                "Deal seven tableau piles: the first holds one card, the second two, and so on to seven, with only each pile's top card face up. The rest of the deck forms the stock.",
                "Build tableau piles down in alternating colors.",
                "Move Aces to the foundations as they appear, then build each suit up to King.",
                "Only Kings can fill an empty tableau pile.",
                "In 1-card draw, flip one stock card at a time. In 3-card draw, flip three.",
                "When the stock is empty, recycle the waste back into it and keep going.",
                "You win by moving all 52 cards to the foundations."
            ]
        case .freecell:
            return [
                "Deal all 52 cards face up into eight cascades (four with 7 cards, four with 6 cards).",
                "Build cascades down in alternating colors.",
                "Use the four free cells as temporary storage for one card each.",
                "Build the foundations up by suit from Ace to King.",
                "Any card can move to an empty cascade.",
                "You win by moving all 52 cards to the foundations."
            ]
        case .yukon:
            return [
                "Deal seven tableau piles: the first holds one face-up card, and each pile after adds one more face-down card beneath five face-up cards. All 52 cards are dealt — there is no stock.",
                "Move any face-up card along with all cards on top of it, even if they are not in sequence.",
                "The moving group's bottom card must land on a card of the opposite color, one rank higher.",
                "Build the foundations up by suit from Ace to King.",
                "Only Kings (with any cards stacked on them) can fill an empty pile.",
                "Face-down cards turn face up when they become the top of a pile.",
                "You win by moving all 52 cards to the foundations."
            ]
        case .spider:
            return [
                "Deal two decks (104 cards) into ten tableau piles: six cards in each of the first four piles and five in the rest, with only the top card face up. The remaining 50 cards form the stock.",
                "A card can move onto any card one rank higher, regardless of suit. Nothing can be placed on an Ace.",
                "Several cards move together only as a face-up run of one suit in descending order.",
                "Any card or movable run can fill an empty pile.",
                "Tap the stock to deal one face-up card onto every pile. You cannot deal while any pile is empty.",
                "A completed King-to-Ace run of one suit is removed from the tableau automatically.",
                "Face-down cards turn face up when they become the top of a pile.",
                "You win by completing all eight runs."
            ]
        case .pyramid:
            return [
                "Deal 28 cards face up into a seven-row pyramid. The remaining 24 cards form the stock.",
                "Remove pairs of exposed cards whose ranks total 13. Ace counts 1, Jack 11, and Queen 12.",
                "Kings count 13 on their own and are removed singly.",
                "A card is exposed once neither card covering it remains. A card whose only cover is its matching partner can be removed together with it.",
                "Tap the stock to draw one card to the waste — the top waste card can pair with exposed pyramid cards.",
                "When the stock runs out, recycle the waste back into it — at most twice.",
                "You win by removing all 28 pyramid cards. The stock and waste do not need to be empty."
            ]
        case .tripeaks:
            return [
                "Deal 28 cards into three overlapping peaks, with three face-down rows under a face-up base row of ten. One card starts the waste, and the remaining 23 form the stock.",
                "Play any uncovered card that is one rank above or below the top waste card, regardless of suit. It becomes the new target.",
                "Ranks wrap around: a King plays on an Ace and an Ace plays on a King or a Two.",
                "A face-down card flips face up once both cards covering it are removed.",
                "Tap the stock to flip one card onto the waste. You get one pass through the stock — no recycles.",
                "You win by clearing all 28 peak cards. The stock and waste do not need to be empty."
            ]
        case .golf:
            return [
                "Deal 35 cards face up into seven columns of five. One card starts the waste, and the remaining 16 form the stock.",
                "Play any exposed column card that is one rank above or below the top waste card, regardless of suit. It becomes the new target.",
                "Ranks never wrap: an Ace connects only to a Two, and a King only to a Queen.",
                "Nothing plays on a King — once one tops the waste, flip the stock to bury it.",
                "Tap the stock to flip one card onto the waste. You get one pass through the stock — no recycles.",
                "The hole ends when you clear all 35 column cards, or when the stock is spent and nothing plays.",
                "A match is nine holes, and the lowest total wins. Switching games keeps the match — it resumes when you return to Golf."
            ]
        case .fortyThieves:
            return [
                "Deal two decks (104 cards) into ten tableau columns of four face-up cards. The remaining 64 cards form the stock.",
                "Build tableau columns down by suit, one rank at a time. Only the top card of a column can move, so sequences never move together.",
                "Any single available card — an exposed tableau card or the top waste card — can fill an empty column.",
                "Build the eight foundations up by suit from Ace to King, two per suit. Cards placed on a foundation never return to play.",
                "Tap the stock at any time to flip one card onto the waste. You get one pass through the stock — no recycles.",
                "You win by moving all 104 cards to the foundations. The game is lost when the stock is spent and no legal move remains."
            ]
        case .canfield:
            return [
                "Deal 13 cards into the reserve with the top card face up, one face-up base card onto the first foundation, and one face-up card onto each of four tableau piles. The remaining 34 cards form the stock.",
                "All four foundations start at the base card's rank and build up by suit, wrapping from King to Ace. Cards placed on a foundation never return to play.",
                "Build tableau piles down in alternating colors, wrapping from Ace to King. Piles move onto each other only as a whole, though the exposed top card can always play to a foundation.",
                "An empty tableau pile fills immediately from the reserve. Once the reserve is empty, fill empty piles with the top waste card whenever you choose.",
                "The reserve's top card is always available to play on foundations or tableau piles.",
                "Tap the stock to turn three cards onto the waste. When it runs out, tap again to turn the waste back into a new stock — redeals are unlimited.",
                "You win by moving all 52 cards to the foundations."
            ]
        case .scorpion:
            return [
                "Deal 49 cards into seven tableau piles of seven. The first four piles hide their bottom three cards face down, while the last three are fully face up. The remaining three cards form the stock.",
                "A card can move only onto the card one rank higher of its own suit. Nothing can be placed on an Ace.",
                "Move any face-up card along with all cards on top of it, even if they are not in sequence.",
                "Only Kings (with any cards stacked on them) can fill an empty pile.",
                "Tap the stock to deal its three cards face up, one onto each of the first three piles. You can deal at any time — but only once.",
                "A completed King-to-Ace run of one suit is removed from the tableau automatically.",
                "Face-down cards turn face up when they become the top of a pile.",
                "You win by completing all four runs."
            ]
        }
    }

    private var scoringRowsForCurrentVariant: [ScoringRow] {
        switch gameVariant {
        case .klondike:
            return scoringRows
        case .freecell:
            return [
                ScoringRow(move: "Move cards", points: 0, note: "FreeCell tracks time and completion."),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .yukon:
            return [
                ScoringRow(move: "Tableau to Foundation", points: Scoring.delta(for: .tableauToFoundation), note: nil),
                ScoringRow(move: "Turn over Tableau card", points: Scoring.delta(for: .turnOverTableauCard), note: nil),
                ScoringRow(move: "Foundation to Tableau", points: Scoring.delta(for: .foundationToTableau), note: nil),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .spider:
            return [
                ScoringRow(
                    move: "Start of game",
                    points: Scoring.spiderInitialScore,
                    note: "Classic Spider scoring starts every game with this balance."
                ),
                ScoringRow(move: "Any move or stock deal", points: Scoring.delta(for: .spiderMove), note: nil),
                ScoringRow(move: "Complete a run", points: Scoring.delta(for: .spiderCompletedRun), note: nil),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .pyramid:
            return [
                ScoringRow(move: "Remove a pair", points: Scoring.delta(for: .removePyramidPair), note: nil),
                ScoringRow(move: "Remove a King", points: Scoring.delta(for: .removePyramidKing), note: nil),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .tripeaks:
            return [
                ScoringRow(
                    move: "Discard onto the waste",
                    points: Scoring.delta(for: .triPeaksChainDiscard(chainLength: 1)),
                    note: "Each consecutive discard is worth one more: 1, 2, 3…"
                ),
                ScoringRow(
                    move: "Flip a stock card",
                    points: Scoring.delta(for: .triPeaksStockFlip),
                    note: "Also resets the chain."
                ),
                ScoringRow(move: "Clear a peak", points: Scoring.delta(for: .triPeaksPeakClear), note: nil),
                ScoringRow(
                    move: "Clear the board",
                    points: Scoring.delta(for: .triPeaksBoardClear),
                    note: "Replaces the third peak's bonus."
                ),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .golf:
            return [
                ScoringRow(
                    move: "Play a card onto the waste",
                    points: Scoring.delta(for: .golfBoardPlay),
                    note: "Your score is the cards still on the board."
                ),
                ScoringRow(move: "Flip a stock card", points: 0, note: nil),
                ScoringRow(
                    move: "Clear the board",
                    points: Scoring.delta(for: .golfBoardClear(remainingStockCount: 1)),
                    note: "One point per stock card left — scores below zero are the best results."
                )
            ]
        case .fortyThieves:
            return [
                ScoringRow(move: "Waste to Tableau", points: Scoring.delta(for: .wasteToTableau), note: nil),
                ScoringRow(move: "Waste to Foundation", points: Scoring.delta(for: .wasteToFoundation), note: nil),
                ScoringRow(move: "Tableau to Foundation", points: Scoring.delta(for: .tableauToFoundation), note: nil),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .canfield:
            return [
                ScoringRow(move: "Waste to Tableau", points: Scoring.delta(for: .wasteToTableau), note: nil),
                ScoringRow(move: "Waste to Foundation", points: Scoring.delta(for: .wasteToFoundation), note: nil),
                ScoringRow(move: "Reserve to Tableau", points: Scoring.delta(for: .reserveToTableau), note: nil),
                ScoringRow(move: "Reserve to Foundation", points: Scoring.delta(for: .reserveToFoundation), note: nil),
                ScoringRow(move: "Tableau to Foundation", points: Scoring.delta(for: .tableauToFoundation), note: nil),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        case .scorpion:
            return [
                ScoringRow(move: "Turn over Tableau card", points: Scoring.delta(for: .turnOverTableauCard), note: nil),
                ScoringRow(move: "Complete a run", points: Scoring.delta(for: .scorpionCompletedRun), note: nil),
                ScoringRow(
                    move: "Win time bonus",
                    points: Scoring.timedMaxBonusDrawThree,
                    note: "Reduced by elapsed time."
                )
            ]
        }
    }
}

#Preview {
    NavigationStack {
        RulesAndScoringView()
    }
}
