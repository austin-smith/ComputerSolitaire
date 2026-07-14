import Foundation

/// A playable game: a variant plus its rule-defining configuration. Klondike's
/// draw counts and Spider's suit counts are distinct games — each mode keeps
/// its own saved session and its own statistics. Raw values key persistence;
/// single-mode variants reuse their variant's raw value so existing saves and
/// statistics carry over.
/// Cases are declared in presentation order, mirroring `GameVariant`; modes
/// within a variant run easiest to hardest.
enum GameMode: String, CaseIterable, Codable {
    case klondikeDrawOne = "klondike.draw1"
    case klondikeDrawThree = "klondike.draw3"
    case spiderOneSuit = "spider.suits1"
    case spiderTwoSuits = "spider.suits2"
    case spiderFourSuits = "spider.suits4"
    case freecell
    case tripeaks
    case pyramid
    case golf
    case fortyThieves = "fortythieves"
    case yukon
    case scorpion
    case canfield

    var variant: GameVariant {
        switch self {
        case .klondikeDrawOne, .klondikeDrawThree:
            return .klondike
        case .freecell:
            return .freecell
        case .yukon:
            return .yukon
        case .spiderOneSuit, .spiderTwoSuits, .spiderFourSuits:
            return .spider
        case .pyramid:
            return .pyramid
        case .tripeaks:
            return .tripeaks
        case .golf:
            return .golf
        case .fortyThieves:
            return .fortyThieves
        case .scorpion:
            return .scorpion
        case .canfield:
            return .canfield
        }
    }

    /// The stock draw mode this game deals with; nil for variants without one.
    var drawMode: DrawMode? {
        switch self {
        case .klondikeDrawOne:
            return .one
        case .klondikeDrawThree:
            return .three
        case .freecell, .yukon, .spiderOneSuit, .spiderTwoSuits, .spiderFourSuits, .pyramid,
             .tripeaks, .golf, .fortyThieves, .scorpion, .canfield:
            return nil
        }
    }

    /// The suit count this game deals with; nil for variants without one.
    var spiderSuitCount: SpiderSuitCount? {
        switch self {
        case .spiderOneSuit:
            return .one
        case .spiderTwoSuits:
            return .two
        case .spiderFourSuits:
            return .four
        case .klondikeDrawOne, .klondikeDrawThree, .freecell, .yukon, .pyramid, .tripeaks, .golf,
             .fortyThieves, .scorpion, .canfield:
            return nil
        }
    }

    /// The mode's qualifier within its variant (draw count, suit count);
    /// single-mode variants fall back to the variant's title.
    var optionTitle: String {
        drawMode?.title ?? spiderSuitCount?.title ?? variant.title
    }

    /// The qualifier that distinguishes this mode from its variant siblings
    /// ("3-card", "2 Suits"); nil for single-mode variants.
    var qualifier: String? {
        guard GameMode.modes(for: variant).count > 1 else { return nil }
        return optionTitle
    }

    /// The mode's full display name: qualified for multi-mode variants
    /// ("Klondike · 3-card"), the plain variant title otherwise.
    var displayTitle: String {
        guard let qualifier else { return variant.title }
        return "\(variant.title) · \(qualifier)"
    }

    /// The mode a game of `variant` plays when dealt with the given
    /// configuration; configuration that doesn't apply to the variant is
    /// ignored.
    init(
        variant: GameVariant,
        drawMode: DrawMode = .three,
        spiderSuitCount: SpiderSuitCount = .two
    ) {
        switch variant {
        case .klondike:
            self = drawMode == .one ? .klondikeDrawOne : .klondikeDrawThree
        case .freecell:
            self = .freecell
        case .yukon:
            self = .yukon
        case .spider:
            switch spiderSuitCount {
            case .one:
                self = .spiderOneSuit
            case .two:
                self = .spiderTwoSuits
            case .four:
                self = .spiderFourSuits
            }
        case .pyramid:
            self = .pyramid
        case .tripeaks:
            self = .tripeaks
        case .golf:
            self = .golf
        case .fortyThieves:
            self = .fortyThieves
        case .scorpion:
            self = .scorpion
        case .canfield:
            self = .canfield
        }
    }

    /// All playable modes of a variant, in picker order.
    static func modes(for variant: GameVariant) -> [GameMode] {
        allCases.filter { $0.variant == variant }
    }
}
