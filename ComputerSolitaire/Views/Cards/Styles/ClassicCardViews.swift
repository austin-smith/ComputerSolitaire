import SwiftUI

// The "Classic" (parchment) card style. Shared card behavior and the style
// dispatcher live in CardView.swift.

enum ClassicCardStyle {
    static let info = CardStyleInfo(title: "Classic", subtitle: "Parchment")
}

private enum ClassicPalette {
    static let parchment = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let redInk = Color(red: 0.72, green: 0.16, blue: 0.18)
    static let blackInk = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let ornament = Color(red: 0.66, green: 0.58, blue: 0.48)

    static func ink(for suit: Suit) -> Color {
        suit.isRed ? redInk : blackInk
    }
}

/// The classic style's lacquer and trim for each CardBackColor identity.
/// Navy keeps the shipped values so existing decks look unchanged.
private struct ClassicBackColorway {
    let backColorID: String
    let lacquer: Color
    let trim: Color

    static let navy = ClassicBackColorway(
        backColorID: CardBackColor.navy.id,
        lacquer: Color(red: 0.18, green: 0.26, blue: 0.52),
        trim: Color(red: 0.78, green: 0.85, blue: 0.95)
    )
    static let crimson = ClassicBackColorway(
        backColorID: CardBackColor.crimson.id,
        lacquer: Color(red: 0.48, green: 0.15, blue: 0.18),
        trim: Color(red: 0.95, green: 0.82, blue: 0.82)
    )
    static let forest = ClassicBackColorway(
        backColorID: CardBackColor.forest.id,
        lacquer: Color(red: 0.13, green: 0.34, blue: 0.22),
        trim: Color(red: 0.80, green: 0.92, blue: 0.83)
    )
    static let plum = ClassicBackColorway(
        backColorID: CardBackColor.plum.id,
        lacquer: Color(red: 0.32, green: 0.17, blue: 0.46),
        trim: Color(red: 0.88, green: 0.81, blue: 0.95)
    )

    static let all: [ClassicBackColorway] = [navy, crimson, forest, plum]

    static func matching(_ back: CardBackColor) -> ClassicBackColorway {
        all.first { $0.backColorID == back.id } ?? navy
    }
}

struct ClassicCardFrontView: View {
    let card: Card
    let cardSize: CGSize
    let isSelected: Bool

    var body: some View {
        let chrome = CardChrome(cardWidth: cardSize.width, isSelected: isSelected)
        let inkColor = ClassicPalette.ink(for: card.suit)
        // Rank in the top-left corner, suit in the top-right, mirrored 180 on
        // the bottom edge.
        let cornerMark = HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(card.rank.label)
                .font(.system(size: cardSize.width * 0.28, weight: .bold, design: .serif))
            Spacer(minLength: 0)
            Image(systemName: card.suit.symbolName)
                .font(.system(size: cardSize.width * 0.2, weight: .semibold))
        }

        ZStack {
            ClassicCardBase(fill: ClassicPalette.parchment, chrome: chrome)
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.clear],
                                startPoint: UnitPoint.topLeading,
                                endPoint: UnitPoint.bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.cornerRadius * 0.92, style: .continuous)
                        .strokeBorder(ClassicPalette.ornament.opacity(0.6), lineWidth: 1)
                        .padding(cardSize.width * 0.06)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.cornerRadius * 0.78, style: .continuous)
                        .strokeBorder(
                            ClassicPalette.ornament.opacity(0.45),
                            style: StrokeStyle(lineWidth: 0.6, dash: [4, 3])
                        )
                        .padding(cardSize.width * 0.1)
                )

            cornerMark
                .foregroundStyle(inkColor)
                .padding(cardSize.width * 0.1)
                .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.top)

            cornerMark
                .foregroundStyle(inkColor)
                .rotationEffect(.degrees(180))
                .padding(cardSize.width * 0.1)
                .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.bottom)

            Image(systemName: card.suit.symbolName)
                .font(.system(size: cardSize.width * 0.55, weight: .regular))
                .foregroundStyle(inkColor.opacity(0.12))
                .rotationEffect(.degrees(8))
                .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.center)
        }
    }
}

struct ClassicCardBackView: View {
    let cardSize: CGSize
    let isSelected: Bool

    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id

    var body: some View {
        let chrome = CardChrome(cardWidth: cardSize.width, isSelected: isSelected)
        let colorway = ClassicBackColorway.matching(.from(rawValue: cardBackColorRawValue))

        ZStack {
            ClassicCardBase(fill: colorway.lacquer, chrome: chrome)
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.cornerRadius * 0.92, style: .continuous)
                        .strokeBorder(colorway.trim.opacity(0.55), lineWidth: 1)
                        .padding(cardSize.width * 0.08)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.cornerRadius * 0.8, style: .continuous)
                        .strokeBorder(colorway.trim.opacity(0.35), style: StrokeStyle(lineWidth: 0.6, dash: [5, 3]))
                        .padding(cardSize.width * 0.12)
                )

            ClassicCardBackPattern()
                .padding(cardSize.width * 0.18)
        }
    }
}

/// Standalone classic card back (stock pile, deck art).
struct ClassicStandaloneCardBackView: View {
    let cardSize: CGSize

    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id

    var body: some View {
        let cornerRadius = cardSize.width * 0.12
        let colorway = ClassicBackColorway.matching(.from(rawValue: cardBackColorRawValue))

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorway.lacquer)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(colorway.trim.opacity(0.5), lineWidth: 1)
                        .padding(cardSize.width * 0.06)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(colorway.trim.opacity(0.25), style: StrokeStyle(lineWidth: 0.6, dash: [5, 3]))
                        .padding(cardSize.width * 0.1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

            ClassicCardBackPattern()
                .padding(cardSize.width * 0.18)
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }
}

private struct ClassicCardBase: View {
    let fill: Color
    let chrome: CardChrome

    var body: some View {
        RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous)
                    .stroke(chrome.borderColor, lineWidth: chrome.borderWidth)
            )
            .shadow(color: chrome.shadowColor, radius: chrome.shadowRadius, x: 0, y: chrome.shadowYOffset)
    }
}

private struct ClassicCardBackPattern: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                Path { path in
                    let step: CGFloat = 10
                    var x: CGFloat = 0
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                Path { path in
                    let step: CGFloat = 10
                    var y: CGFloat = 0
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                }
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
    }
}
