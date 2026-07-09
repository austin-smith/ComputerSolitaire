import SwiftUI

// Shared card infrastructure: the style catalog, the environment plumbing, and
// the CardView dispatcher with behavior common to every card style (flip
// animation, tilt, selection scale, hint wiggle). Style-specific rendering
// lives in ClassicCardViews.swift and PixelCardViews.swift.

/// Display metadata a card style provides for the settings picker; each style
/// defines its own in its file under Styles/.
struct CardStyleInfo {
    let title: String
    let subtitle: String
}

enum CardStyle: String, CaseIterable, Identifiable {
    case `default`
    case pixel
    // Raw value stays "classic": shipped user preferences and the screenshot
    // UI test launch arguments both store that string.
    case legacy = "classic"

    var id: String { rawValue }

    /// The one dispatch point per style, alongside the view dispatch in CardView.
    var info: CardStyleInfo {
        switch self {
        case .default: DefaultCardStyle.info
        case .legacy: LegacyCardStyle.info
        case .pixel: PixelCardStyle.info
        }
    }

    var title: String { info.title }
    var subtitle: String { info.subtitle }
}

/// Style-agnostic card back color identity. Each card style maps an identity
/// to its own palette (see PixelBackColorway); styles that haven't adopted the
/// setting yet simply ignore it.
struct CardBackColor: Identifiable, Equatable {
    let id: String
    let label: String
    /// Representative color for the settings swatch.
    let swatch: Color

    static let navy = CardBackColor(
        id: "navy", label: "Navy",
        swatch: Color(red: 0.21, green: 0.29, blue: 0.56)
    )
    static let crimson = CardBackColor(
        id: "crimson", label: "Crimson",
        swatch: Color(red: 0.57, green: 0.20, blue: 0.22)
    )
    static let forest = CardBackColor(
        id: "forest", label: "Forest",
        swatch: Color(red: 0.15, green: 0.40, blue: 0.25)
    )
    static let plum = CardBackColor(
        id: "plum", label: "Plum",
        swatch: Color(red: 0.38, green: 0.21, blue: 0.53)
    )

    static let all: [CardBackColor] = [navy, crimson, forest, plum]
    static let defaultValue: CardBackColor = .navy

    static func from(rawValue: String) -> CardBackColor {
        all.first { $0.id == rawValue } ?? defaultValue
    }
}

private struct CardStyleKey: EnvironmentKey {
    static let defaultValue: CardStyle = .default
}

extension EnvironmentValues {
    var cardStyle: CardStyle {
        get { self[CardStyleKey.self] }
        set { self[CardStyleKey.self] = newValue }
    }
}

enum CardTilt {
    static let angleRange: ClosedRange<Double> = -2.0...2.0
}

/// Selection-dependent corner, border, and shadow treatment for card styles
/// that use the standard rounded-rectangle chrome.
struct CardChrome {
    let cornerRadius: CGFloat
    let borderColor: Color
    let borderWidth: CGFloat
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    init(cardWidth: CGFloat, isSelected: Bool) {
        cornerRadius = cardWidth * 0.12
        borderColor = isSelected ? Color.yellow.opacity(0.9) : Color.black.opacity(0.2)
        borderWidth = isSelected ? 3 : 1
        shadowColor = Color.black.opacity(isSelected ? 0.35 : 0.2)
        shadowRadius = isSelected ? 8 : 4
        shadowYOffset = isSelected ? 6 : 2
    }
}

enum HintWiggleStyle {
    static let angles: [Double] = [-1.4, 1.4, -0.8, 0.8, 0]
    static let stepDuration: Double = 0.13
    static let stepSleepNanoseconds: UInt64 = 200_000_000
}

struct HintWiggleModifier: ViewModifier {
    let token: UUID?
    @State private var wiggleAngle: Double = 0
    @State private var wiggleTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(wiggleAngle))
            .onChange(of: token) { _, newToken in
                if newToken == nil {
                    wiggleTask?.cancel()
                    wiggleAngle = 0
                    return
                }
                startHintWiggle()
            }
            .onAppear {
                if token != nil {
                    startHintWiggle()
                }
            }
            .onDisappear {
                wiggleTask?.cancel()
                wiggleAngle = 0
            }
    }

    private func startHintWiggle() {
        wiggleTask?.cancel()
        wiggleTask = Task { @MainActor in
            for angle in HintWiggleStyle.angles {
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: HintWiggleStyle.stepDuration)) {
                    wiggleAngle = angle
                }
                try? await Task.sleep(nanoseconds: HintWiggleStyle.stepSleepNanoseconds)
            }
            wiggleAngle = 0
        }
    }
}

extension View {
    func hintWiggle(token: UUID?) -> some View {
        modifier(HintWiggleModifier(token: token))
    }
}

struct CardView: View {
    let card: Card
    let isSelected: Bool
    let cardSize: CGSize
    let isCardTiltEnabled: Bool
    @Binding var cardTilts: [UUID: Double]
    let hintWiggleToken: UUID?
    let flipOnAppear: Bool
    let flipDelay: Double
    @State private var flipRotation: Double
    @State private var tiltAngle: Double = 0
    @Environment(\.cardStyle) private var cardStyle

    init(
        card: Card,
        isSelected: Bool,
        cardSize: CGSize,
        isCardTiltEnabled: Bool,
        cardTilts: Binding<[UUID: Double]>,
        hintWiggleToken: UUID? = nil,
        flipOnAppear: Bool = false,
        flipDelay: Double = 0
    ) {
        self.card = card
        self.isSelected = isSelected
        self.cardSize = cardSize
        self.isCardTiltEnabled = isCardTiltEnabled
        self._cardTilts = cardTilts
        self.hintWiggleToken = hintWiggleToken
        self.flipOnAppear = flipOnAppear
        self.flipDelay = flipDelay
        let startFaceDown = flipOnAppear && card.isFaceUp
        _flipRotation = State(initialValue: startFaceDown ? 180 : (card.isFaceUp ? 0 : 180))
    }

    var body: some View {
        let frontAngle = flipRotation
        let backAngle = flipRotation - 180
        let frontOpacity = flipRotation < 90 ? 1.0 : 0.0
        let backOpacity = flipRotation < 90 ? 0.0 : 1.0

        ZStack {
            cardFrontView
                .opacity(frontOpacity)
                .rotation3DEffect(.degrees(frontAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.7)

            cardBackView
                .opacity(backOpacity)
                .rotation3DEffect(.degrees(backAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .rotationEffect(.degrees(tiltAngle))
        .hintWiggle(token: hintWiggleToken)
        .scaleEffect(isSelected ? 1.03 : 1)
        .onChange(of: card.isFaceUp) { _, newValue in
            withAnimation(.easeInOut(duration: 0.32)) {
                flipRotation = newValue ? 0 : 180
            }
        }
        .onAppear {
            if flipOnAppear, card.isFaceUp, flipRotation != 0 {
                // easeOut so the rotation is front-loaded like the travel
                // spring — the card visibly turns while it's moving fastest,
                // not after it has mostly arrived.
                withAnimation(.easeOut(duration: 0.3).delay(flipDelay)) {
                    flipRotation = 0
                }
            }
            // No animation: a card entering the hierarchy (dealt, revealed
            // from under another, or restored) is already resting — animating
            // 0 → tilt here reads as the card visibly re-tilting on reveal.
            tiltAngle = isCardTiltEnabled ? resolvedTilt() : 0
        }
        .onChange(of: cardTilts[card.id]) { _, newTilt in
            guard isCardTiltEnabled, let newTilt else { return }
            animateTilt(to: newTilt)
        }
        .onChange(of: isCardTiltEnabled) { _, enabled in
            animateTilt(to: enabled ? resolvedTilt() : 0)
        }
    }

    // Returns the card's stored tilt, assigning a new random one on first use
    // so a card keeps the same lean for as long as it stays in play.
    private func resolvedTilt() -> Double {
        if let existing = cardTilts[card.id] {
            return existing
        }
        let newTilt = Double.random(in: CardTilt.angleRange)
        cardTilts[card.id] = newTilt
        return newTilt
    }

    private func animateTilt(to target: Double) {
        withAnimation(.easeOut(duration: 0.2)) {
            tiltAngle = target
        }
    }

    @ViewBuilder
    private var cardFrontView: some View {
        switch cardStyle {
        case .pixel:
            PixelCardFrontView(card: card, cardSize: cardSize, isSelected: isSelected)
        case .legacy:
            LegacyCardFrontView(card: card, cardSize: cardSize, isSelected: isSelected)
        case .default:
            DefaultCardFrontView(card: card, cardSize: cardSize, isSelected: isSelected)
        }
    }

    @ViewBuilder
    private var cardBackView: some View {
        switch cardStyle {
        case .pixel:
            PixelCardBackView(cardSize: cardSize, isSelected: isSelected)
        case .legacy:
            LegacyCardBackView(cardSize: cardSize, isSelected: isSelected)
        case .default:
            DefaultCardBackView(cardSize: cardSize, isSelected: isSelected)
        }
    }
}

/// Standalone card back (stock pile, deck art) rendered per the active style.
struct CardBackView: View {
    let cardSize: CGSize
    @Environment(\.cardStyle) private var cardStyle

    var body: some View {
        switch cardStyle {
        case .pixel:
            PixelStandaloneCardBackView(cardSize: cardSize)
        case .legacy:
            LegacyStandaloneCardBackView(cardSize: cardSize)
        case .default:
            DefaultStandaloneCardBackView(cardSize: cardSize)
        }
    }
}
