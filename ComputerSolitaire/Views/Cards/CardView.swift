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
    case classic
    case pixel

    var id: String { rawValue }

    /// The one dispatch point per style, alongside the view dispatch in CardView.
    var info: CardStyleInfo {
        switch self {
        case .classic: ClassicCardStyle.info
        case .pixel: PixelCardStyle.info
        }
    }

    var title: String { info.title }
    var subtitle: String { info.subtitle }
}

private struct CardStyleKey: EnvironmentKey {
    static let defaultValue: CardStyle = .classic
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
                withAnimation(.easeInOut(duration: 0.22).delay(flipDelay)) {
                    flipRotation = 0
                }
            }
            let targetTilt: Double
            if isCardTiltEnabled {
                if let existing = cardTilts[card.id] {
                    targetTilt = existing
                } else {
                    let newTilt = Double.random(in: CardTilt.angleRange)
                    cardTilts[card.id] = newTilt
                    targetTilt = newTilt
                }
            } else {
                targetTilt = 0
            }
            animateTilt(to: targetTilt)
        }
        .onChange(of: cardTilts[card.id]) { _, newTilt in
            guard isCardTiltEnabled, let newTilt else { return }
            animateTilt(to: newTilt)
        }
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
        case .classic:
            ClassicCardFrontView(card: card, cardSize: cardSize, isSelected: isSelected)
        }
    }

    @ViewBuilder
    private var cardBackView: some View {
        switch cardStyle {
        case .pixel:
            PixelCardBackView(cardSize: cardSize, isSelected: isSelected)
        case .classic:
            ClassicCardBackView(cardSize: cardSize, isSelected: isSelected)
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
        case .classic:
            ClassicStandaloneCardBackView(cardSize: cardSize)
        }
    }
}
