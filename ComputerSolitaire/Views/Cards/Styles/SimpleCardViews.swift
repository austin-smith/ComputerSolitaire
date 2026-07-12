import SwiftUI

// The "Simple" card style: a clean white face with the rank at the top and a
// single full-opacity suit glyph in the center. No mirrored bottom marks.
// Shared card behavior and the style dispatcher live in CardView.swift.

enum SimpleCardStyle {
    static let info = CardStyleInfo(title: "Simple", subtitle: "Clean")
}

/// Royal artwork anchored to the bottom-right corner of the face, replacing
/// the center suit glyph. Cards without art keep the plain glyph face.
private enum SimpleCardArt {
    static func imageName(for card: Card) -> String? {
        switch (card.rank, card.suit) {
        case (.queen, .hearts): "Simple/QueenOfHearts"
        case (.queen, .clubs): "Simple/QueenOfClubs"
        case (.queen, .spades): "Simple/QueenOfSpades"
        case (.queen, .diamonds): "Simple/QueenOfDiamonds"
        case (.jack, .hearts): "Simple/JackOfHearts"
        case (.jack, .clubs): "Simple/JackOfClubs"
        case (.jack, .spades): "Simple/JackOfSpades"
        case (.jack, .diamonds): "Simple/JackOfDiamonds"
        case (.king, .hearts): "Simple/KingOfHearts"
        case (.king, .clubs): "Simple/KingOfClubs"
        case (.king, .spades): "Simple/KingOfSpades"
        case (.king, .diamonds): "Simple/KingOfDiamonds"
        default: nil
        }
    }
}

private enum SimplePalette {
    static let face = Color.white
    static let red = Color(red: 0.80, green: 0.12, blue: 0.16)
    static let black = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let backTrim = Color.white.opacity(0.7)

    static func ink(for suit: Suit) -> Color {
        suit.isRed ? red : black
    }
}

/// The simple style's back tint for each CardBackColor identity.
private struct SimpleBackColorway {
    let backColorID: String
    let base: Color

    static let navy = SimpleBackColorway(
        backColorID: CardBackColor.navy.id,
        base: Color(red: 0.19, green: 0.28, blue: 0.52)
    )
    static let crimson = SimpleBackColorway(
        backColorID: CardBackColor.crimson.id,
        base: Color(red: 0.55, green: 0.19, blue: 0.21)
    )
    static let forest = SimpleBackColorway(
        backColorID: CardBackColor.forest.id,
        base: Color(red: 0.16, green: 0.40, blue: 0.28)
    )
    static let plum = SimpleBackColorway(
        backColorID: CardBackColor.plum.id,
        base: Color(red: 0.36, green: 0.20, blue: 0.50)
    )

    static let all: [SimpleBackColorway] = [navy, crimson, forest, plum]

    static func matching(_ back: CardBackColor) -> SimpleBackColorway {
        all.first { $0.backColorID == back.id } ?? navy
    }
}

struct SimpleCardFrontView: View {
    let card: Card
    let cardSize: CGSize
    let isSelected: Bool

    var body: some View {
        let chrome = CardChrome(cardWidth: cardSize.width, isSelected: isSelected)
        let inkColor = SimplePalette.ink(for: card.suit)

        ZStack {
            SimpleCardBase(fill: SimplePalette.face, chrome: chrome)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(card.rank.label)
                    .font(.custom("Charter-Bold", size: cardSize.width * 0.27))
                Spacer(minLength: 0)
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: cardSize.width * 0.22, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(inkColor)
            .padding(cardSize.width * 0.08)
            .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.top)

            if let artName = SimpleCardArt.imageName(for: card) {
                // Royal figure planted in the bottom-right corner, dress and
                // trailing arm trimmed by the card bounds; sized to stay
                // clear of the top marks. Jack artwork carries extra headroom
                // in its canvas, so it gets a small extra nudge into the
                // corner to line up with the kings and queens.
                let isJack = card.rank == .jack
                Image(artName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardSize.width * 0.88)
                    .offset(x: cardSize.width * (isJack ? 0.19 : 0.17),
                            y: cardSize.width * (isJack ? 0.36 : 0.32))
                    .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                // Optically centered in the region below the top marks, not
                // the full card, so the face doesn't read bottom-heavy.
                Image(systemName: card.suit.symbolName)
                    .font(.system(size: cardSize.width * 0.56, weight: .regular))
                    .foregroundStyle(inkColor)
                    .offset(y: cardSize.width * 0.14)
                    .frame(width: cardSize.width, height: cardSize.height, alignment: Alignment.center)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct SimpleCardBackView: View {
    let cardSize: CGSize
    let isSelected: Bool

    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id

    var body: some View {
        let chrome = CardChrome(cardWidth: cardSize.width, isSelected: isSelected)
        let colorway = SimpleBackColorway.matching(.from(rawValue: cardBackColorRawValue))

        ZStack {
            SimpleCardBase(fill: colorway.base, chrome: chrome)
                .overlay(
                    RoundedRectangle(cornerRadius: chrome.cornerRadius * 0.85, style: .continuous)
                        .strokeBorder(SimplePalette.backTrim, lineWidth: 1.5)
                        .padding(cardSize.width * 0.09)
                )
        }
    }
}

/// Standalone simple card back (stock pile, deck art).
struct SimpleStandaloneCardBackView: View {
    let cardSize: CGSize

    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id

    var body: some View {
        let cornerRadius = cardSize.width * 0.12
        let colorway = SimpleBackColorway.matching(.from(rawValue: cardBackColorRawValue))

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorway.base)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * 0.85, style: .continuous)
                    .strokeBorder(SimplePalette.backTrim, lineWidth: 1.5)
                    .padding(cardSize.width * 0.09)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            .frame(width: cardSize.width, height: cardSize.height)
    }
}

private struct SimpleCardBase: View {
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
