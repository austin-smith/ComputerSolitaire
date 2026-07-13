import SwiftUI

/// End-of-hole interstitial: shows the finished hole's strokes and the match
/// standing, and advances the match on the player's tap. A dead hole (stock
/// spent, nothing plays) also offers Undo — nothing is recorded until the
/// player advances, so backing out is always safe.
struct GolfHoleCompleteOverlay: View {
    let holeNumber: Int
    let holeScore: Int
    let matchTotalThroughHole: Int
    let isFinalHole: Bool
    let didClearBoard: Bool
    let onAdvance: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(didClearBoard ? "Hole Cleared!" : "Hole Over")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Hole \(holeNumber) of \(GolfMatchState.holeCount): \(holeScore) strokes")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(GolfScoreFormatting.parStanding(
                total: matchTotalThroughHole,
                holesPlayed: holeNumber
            ))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Button(isFinalHole ? "Finish Match" : "Next Hole") {
                onAdvance()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0235, green: 0.4431, blue: 0.7176))
            if !didClearBoard {
                Button("Undo") {
                    onUndo()
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .golfOverlayChrome()
    }
}

/// Match-complete scorecard: nine hole scores, the total, and its standing
/// against par. Presents over the final board (it derives from persisted
/// state, so quitting here re-presents it on relaunch).
struct GolfMatchSummaryOverlay: View {
    let match: GolfMatchState
    let onNewMatch: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Match Complete")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(Array(match.completedHoleScores.enumerated()), id: \.offset) { index, score in
                    scorecardRow(holeNumber: index + 1, score: score)
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text(GolfScoreFormatting.parStanding(
                total: match.runningTotal,
                holesPlayed: GolfMatchState.holeCount
            ))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Button("New Match") {
                onNewMatch()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0235, green: 0.4431, blue: 0.7176))
        }
        .golfOverlayChrome()
    }

    private func scorecardRow(holeNumber: Int, score: Int) -> some View {
        // A hole at zero or under was cleared — Golf's best results — so it
        // reads emphasized.
        let holeWasCleared = score <= 0
        return GridRow {
            Text("Hole \(holeNumber)")
                .foregroundStyle(.white.opacity(0.75))
                .gridColumnAlignment(.leading)
            Text("\(score)")
                .monospacedDigit()
                .foregroundStyle(holeWasCleared ? .white : .white.opacity(0.75))
                .fontWeight(holeWasCleared ? .bold : .regular)
        }
    }
}

private extension View {
    /// The Golf end-of-play presentation, matching the win overlay's chrome:
    /// a dimming scrim behind a dark rounded panel, contained and modal to
    /// VoiceOver because the board underneath is finished and inert — the
    /// overlay's own controls are the only actions.
    func golfOverlayChrome() -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

enum GolfScoreFormatting {
    /// "Total 32 — 8 under par pace" framing. Par is 45 across nine holes,
    /// so the pace through N holes is 5N; after the ninth hole the pace IS
    /// par, and the wording drops "pace".
    static func parStanding(total: Int, holesPlayed: Int) -> String {
        let parPace = (GolfMatchState.parTotal / GolfMatchState.holeCount) * holesPlayed
        let difference = total - parPace
        let isFinal = holesPlayed == GolfMatchState.holeCount
        let reference = isFinal ? "par" : "par pace"
        let standing: String
        if difference == 0 {
            standing = "even with \(reference)"
        } else if difference < 0 {
            standing = "\(-difference) under \(reference)"
        } else {
            standing = "\(difference) over \(reference)"
        }
        return "Total \(total) — \(standing)"
    }
}

#Preview("Hole Complete") {
    GolfHoleCompleteOverlay(
        holeNumber: 3,
        holeScore: -2,
        matchTotalThroughHole: 11,
        isFinalHole: false,
        didClearBoard: true,
        onAdvance: {},
        onUndo: {}
    )
}

#Preview("Match Summary") {
    GolfMatchSummaryOverlay(
        match: GolfMatchState(completedHoleScores: [3, 7, -2, 12, 0, 5, 9, 4, 2]),
        onNewMatch: {}
    )
}
