import SwiftUI

// TODO: Separate the static sprite catalog from the pixel renderer without
// fragmenting the card-style UI, then remove this exception.
// swiftlint:disable file_length

enum PixelCardStyle {
    static let info = CardStyleInfo(title: "Pixel", subtitle: "8-bit Retro")
}

// MARK: - Pixel Art Color Palette

enum PixelPalette {
    // Card face
    static let cardFace = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let outline = Color(red: 0.13, green: 0.12, blue: 0.15)

    // Suit inks
    static let red = Color(red: 0.80, green: 0.14, blue: 0.16)
    static let redLight = Color(red: 0.93, green: 0.42, blue: 0.40)
    static let black = Color(red: 0.13, green: 0.12, blue: 0.15)
    static let blackLight = Color(red: 0.38, green: 0.38, blue: 0.44)

    // Face card palette
    static let skinTone = Color(red: 0.95, green: 0.80, blue: 0.63)
    static let skinShadow = Color(red: 0.80, green: 0.60, blue: 0.44)
    static let gold = Color(red: 0.89, green: 0.71, blue: 0.22)
    static let robeRed = Color(red: 0.70, green: 0.15, blue: 0.20)
    static let robeRedDark = Color(red: 0.48, green: 0.09, blue: 0.14)
    static let robeBlue = Color(red: 0.22, green: 0.32, blue: 0.66)
    static let robeBlueDark = Color(red: 0.13, green: 0.19, blue: 0.44)
    static let hair = Color(red: 0.32, green: 0.22, blue: 0.13)
    static let ermine = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let accent = Color(red: 0.83, green: 0.22, blue: 0.25)

    static func suitColor(for suit: Suit) -> Color {
        suit.isRed ? red : black
    }
}

/// The pixel style's tone ramp for each CardBackColor identity: deep field,
/// muted weave, mid intersections, bright frame.
struct PixelBackColorway {
    let backColorID: String
    let deep: Color
    let muted: Color
    let mid: Color
    let bright: Color

    static let navy = PixelBackColorway(
        backColorID: CardBackColor.navy.id,
        deep: Color(red: 0.11, green: 0.16, blue: 0.37),
        muted: Color(red: 0.18, green: 0.25, blue: 0.50),
        mid: Color(red: 0.21, green: 0.29, blue: 0.56),
        bright: Color(red: 0.55, green: 0.64, blue: 0.90)
    )
    static let crimson = PixelBackColorway(
        backColorID: CardBackColor.crimson.id,
        deep: Color(red: 0.38, green: 0.10, blue: 0.12),
        muted: Color(red: 0.50, green: 0.16, blue: 0.18),
        mid: Color(red: 0.57, green: 0.20, blue: 0.22),
        bright: Color(red: 0.92, green: 0.58, blue: 0.58)
    )
    static let forest = PixelBackColorway(
        backColorID: CardBackColor.forest.id,
        deep: Color(red: 0.07, green: 0.24, blue: 0.14),
        muted: Color(red: 0.12, green: 0.34, blue: 0.21),
        mid: Color(red: 0.15, green: 0.40, blue: 0.25),
        bright: Color(red: 0.55, green: 0.80, blue: 0.62)
    )
    static let plum = PixelBackColorway(
        backColorID: CardBackColor.plum.id,
        deep: Color(red: 0.24, green: 0.11, blue: 0.34),
        muted: Color(red: 0.33, green: 0.17, blue: 0.46),
        mid: Color(red: 0.38, green: 0.21, blue: 0.53),
        bright: Color(red: 0.74, green: 0.60, blue: 0.90)
    )

    static let all: [PixelBackColorway] = [navy, crimson, forest, plum]

    static func matching(_ back: CardBackColor) -> PixelBackColorway {
        all.first { $0.backColorID == back.id } ?? navy
    }
}

extension PixelPalette {
    static func suitHighlight(for suit: Suit) -> Color {
        suit.isRed ? redLight : blackLight
    }
}

// MARK: - Card Silhouette (stepped pixel corners)

struct PixelCardShape: InsettableShape {
    /// One virtual pixel unit (card width / PixelCardArt.gridWidth).
    let pixelSize: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let maxCorner = min(insetRect.width, insetRect.height) / 2
        let step = max(1, min(pixelSize, floor(maxCorner / 3)))
        let corner = step * 3

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + corner, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - corner, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - step * 2, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - step * 2, y: insetRect.minY + step))
        path.addLine(to: CGPoint(x: insetRect.maxX - step, y: insetRect.minY + step))
        path.addLine(to: CGPoint(x: insetRect.maxX - step, y: insetRect.minY + step * 2))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + step * 2))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - step * 2))
        path.addLine(to: CGPoint(x: insetRect.maxX - step, y: insetRect.maxY - step * 2))
        path.addLine(to: CGPoint(x: insetRect.maxX - step, y: insetRect.maxY - step))
        path.addLine(to: CGPoint(x: insetRect.maxX - step * 2, y: insetRect.maxY - step))
        path.addLine(to: CGPoint(x: insetRect.maxX - step * 2, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX + step * 2, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX + step * 2, y: insetRect.maxY - step))
        path.addLine(to: CGPoint(x: insetRect.minX + step, y: insetRect.maxY - step))
        path.addLine(to: CGPoint(x: insetRect.minX + step, y: insetRect.maxY - step * 2))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY - step * 2))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + step * 2))
        path.addLine(to: CGPoint(x: insetRect.minX + step, y: insetRect.minY + step * 2))
        path.addLine(to: CGPoint(x: insetRect.minX + step, y: insetRect.minY + step))
        path.addLine(to: CGPoint(x: insetRect.minX + step * 2, y: insetRect.minY + step))
        path.addLine(to: CGPoint(x: insetRect.minX + step * 2, y: insetRect.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Sprite Storage

/// Palette indices used inside sprite art strings.
enum PixelInk: UInt8 {
    case none = 0
    case ink = 1        // "#" suit color
    case inkHi = 2      // "+" suit highlight
    case outlineDark = 3 // "K"
    case skin = 4       // "S"
    case skinShade = 5  // "s"
    case gold = 6       // "G"
    case robe = 7       // "R"
    case robeDark = 8   // "D"
    case hair = 9       // "H"
    case white = 10     // "W"
    case accent = 11    // "A"
    case altRobe = 12   // "B" — contrasting garment (blue on red suits, red on black)
}

struct PixelSprite {
    let width: Int
    let height: Int
    let cells: [[UInt8]]

    init(_ art: String) {
        let map: [Character: UInt8] = [
            ".": 0, "#": 1, "+": 2, "K": 3, "S": 4, "s": 5,
            "G": 6, "R": 7, "D": 8, "H": 9, "W": 10, "A": 11, "B": 12
        ]
        let lines = art.split(separator: "\n").map(String.init)
        let spriteWidth = lines.map(\.count).max() ?? 0
        cells = lines.map { line in
            var row = line.map { map[$0] ?? 0 }
            while row.count < spriteWidth { row.append(0) }
            return row
        }
        width = spriteWidth
        height = cells.count
    }
}

// MARK: - Sprite Art

enum PixelSprites {
    // Suits — 7x7, "+" marks the sheen used on large renditions.
    static let spade = PixelSprite("""
    ...#...
    ..###..
    .#+###.
    #######
    #######
    ##.#.##
    ..###..
    """)

    static let heart = PixelSprite("""
    .##.##.
    #+#####
    #+#####
    #######
    .#####.
    ..###..
    ...#...
    """)

    static let diamond = PixelSprite("""
    ...#...
    ..+##..
    .#+###.
    #######
    .#####.
    ..###..
    ...#...
    """)

    static let club = PixelSprite("""
    ..###..
    ..+##..
    #######
    #######
    ##.#.##
    ...#...
    ..###..
    """)

    static func suit(_ suit: Suit) -> PixelSprite {
        switch suit {
        case .spades: return spade
        case .hearts: return heart
        case .diamonds: return diamond
        case .clubs: return club
        }
    }

    // Compact pip suits — 5x5, sized so pip rows and columns never collide.
    static let spadePip = PixelSprite("""
    ..#..
    .###.
    #####
    #####
    ..#..
    """)

    static let heartPip = PixelSprite("""
    .#.#.
    #####
    #####
    .###.
    ..#..
    """)

    static let diamondPip = PixelSprite("""
    ..#..
    .###.
    #####
    .###.
    ..#..
    """)

    static let clubPip = PixelSprite("""
    .###.
    #####
    #####
    ##.##
    ..#..
    """)

    static func pipSuit(_ suit: Suit) -> PixelSprite {
        switch suit {
        case .spades: return spadePip
        case .hearts: return heartPip
        case .diamonds: return diamondPip
        case .clubs: return clubPip
        }
    }

    // Rank glyphs — 5x7 ("10" is 7 wide).
    static let ranks: [String: PixelSprite] = [
        "A": PixelSprite("""
        .###.
        #...#
        #...#
        #####
        #...#
        #...#
        #...#
        """),
        "2": PixelSprite("""
        .###.
        #...#
        ....#
        ...#.
        ..#..
        .#...
        #####
        """),
        "3": PixelSprite("""
        ####.
        ....#
        ..##.
        ....#
        ....#
        #...#
        .###.
        """),
        "4": PixelSprite("""
        ...#.
        ..##.
        .#.#.
        #..#.
        #####
        ...#.
        ...#.
        """),
        "5": PixelSprite("""
        #####
        #....
        ####.
        ....#
        ....#
        #...#
        .###.
        """),
        "6": PixelSprite("""
        .###.
        #....
        #....
        ####.
        #...#
        #...#
        .###.
        """),
        "7": PixelSprite("""
        #####
        ....#
        ...#.
        ..#..
        ..#..
        .#...
        .#...
        """),
        "8": PixelSprite("""
        .###.
        #...#
        #...#
        .###.
        #...#
        #...#
        .###.
        """),
        "9": PixelSprite("""
        .###.
        #...#
        #...#
        .####
        ....#
        ....#
        .###.
        """),
        "10": PixelSprite("""
        .#..##.
        ##.#..#
        .#.#..#
        .#.#..#
        .#.#..#
        .#.#..#
        .#..##.
        """),
        "J": PixelSprite("""
        ..###
        ...#.
        ...#.
        ...#.
        ...#.
        #..#.
        .##..
        """),
        "Q": PixelSprite("""
        .###.
        #...#
        #...#
        #...#
        #.#.#
        #..#.
        .##.#
        """),
        "K": PixelSprite("""
        #...#
        #..#.
        #.#..
        ##...
        #.#..
        #..#.
        #...#
        """)
    ]

    static func rank(_ rank: Rank) -> PixelSprite {
        guard let sprite = ranks[rank.label] else {
            preconditionFailure("Missing pixel-art glyph for rank \(rank.label)")
        }
        return sprite
    }

}

// Face card portraits — 28x35, outlined forms in the classic style.
extension PixelSprites {
    static let king = PixelSprite("""
    ........G..G..G..G..G.......
    .......KGGGGGGGGGGGGGGK.....
    .......KGGAGGGAAGGGAGGK.....
    .......KGGGGGGGGGGGGGGK.....
    .......KHHHHHHHHHHHHHHK.....
    ......KHHSSSSSSSSSSSSHHK....
    ......KHHSSSSSSSSSSSSHHK....
    ......KHHSKSSSSSSSSKSHHK....
    ......KHHSSSSSssSSSSSHHK....
    ......KHHSHHHSSSSHHHSHHK....
    ......KHHHHHHSAASHHHHHHK....
    ......KHHHHHHHHHHHHHHHHK....
    .......KHHHHHHHHHHHHHHK.....
    ........KHHHHHHHHHHHHK......
    ....KKKWWKKHHHHHHHHKKWWKKK..
    ...KRRKWWWWKHHHHHHKWWWWKRRK.
    ..KRRRKWWWWKKHHHHKKWWWWKRRRK
    ..KRRRRKWWWWKHHHHKWWWWKRRRRK
    ..KRRRRKWWWWKKHHKKWWWWKRRRRK
    ..KRRRRRKWWWWKKKKWWWWKRRRRRK
    ..KRRRRRKKWWWWWWWWWWKKRRRRRK
    ..KRRDRRRKKWWWWWWWWKKRRDRRRK
    ..KRRDRRRRKKWWWWWWKKRRRDRRRK
    ..KRRDRRRRRKKWWWWKKRRRRDRRRK
    ..KRRDRRRRRRKWWWWKRRRRRDRRRK
    ..KRRDRRRRRRKWWWWKRRRRRDRRRK
    ..KRRDRRRRRRKWWWWKRRRRRDRRRK
    ..KRRDRRRRRGKWWWWKGRRRRDRRRK
    ..KRRDRRRRGGKWWWWKGGRRRDRRRK
    ..KRRDRRRGGRKWWWWKRGGRRDRRRK
    ..KRRDRRGGRRKWWWWKRRGGRDRRRK
    ..KRRDRGGRRRKWWWWKRRRGGDRRRK
    ..KRRDGGRRRRKWWWWKRRRRGGRRRK
    ..KKKKKKKKKKKKKKKKKKKKKKKKKK
    ............................
    """)

    static let queen = PixelSprite("""
    ..........G...G...G.........
    .........KGGGGGGGGGK........
    .........KGAGGGGGAGK........
    .........KGGGGGGGGGK........
    ........KHHHHHHHHHHHK.......
    .......KHHHSSSSSSHHHK.......
    ......KHHHSSSSSSSSHHHK......
    ......KHHSSKSSSSKSSHHK......
    ......KHHSSSSSSSSSSHHK......
    ......KHHSSSSssSSSSHHK......
    ......KHHSSSSAASSSSHHK......
    ......KHHSSSSSSSSSSHHK......
    ......KHHHKSSSSSSKHHHK......
    ......KHHHKKSSSSKKHHHK......
    .....KHHHHKGGGGGGKHHHHK.....
    .....KHHHKRRRRRRRRKHHHK.....
    .....KHHKRRGGRRGGRRKHHK.....
    ....KHHKRRKAAKKAAKRRKHHK....
    ....KHHKRRKAAAAAAKRRKHHK....
    ....KHHKRRRKAAAAKRRRKHHK....
    ....KHHKRRRRKAAKRRRRKHHK....
    ....KHHKGGGGGGGGGGGGKHHK....
    ...KHHKRRRRRRRRRRRRRRKHHK...
    ...KHKRRRRRRRRRRRRRRRRKHK...
    ...KKRRRDRRRRRRRRRRDRRRKK...
    ..KRRRRRDRRRRRRRRRRDRRRRRK..
    ..KRRRRDRRRRRRRRRRRRDRRRRK..
    ..KRRRGRRGRRGRRGRRGRRGRRRK..
    ..KRRGRRGRRGRRGRRGRRGRRGRK..
    ..KRRRRRRRRRRRRRRRRRRRRRRK..
    ..KRDDRRRRRRRRRRRRRRRRDDRK..
    ..KDDDDRRRRRRRRRRRRRRDDDDK..
    ..KDDDDDDRRRRRRRRRRDDDDDDK..
    ..KDDDDDDDDDDDDDDDDDDDDDDK..
    ..KKKKKKKKKKKKKKKKKKKKKKKK..
    """)

    static let jack = PixelSprite("""
    ....................GAA.....
    ...............KKK..GAA.....
    ............KKKBBBKKGAA.....
    ..........KBBBBBBBBBGGA.....
    .........KBBBBBBBBBBBGK.....
    ........KBBBBBBBBBBBBBBK....
    ........KKKKKKKKKKKKKKKK....
    .......KHHHHHHHHHHHHHHK.....
    ......KHHSSSSSSSSSSSSHHK....
    ......KHHSSSSSSSSSSSSHHK....
    ......KHHSKSSSSSSSSKSHHK....
    ......KHHSSSSSssSSSSSHHK....
    ......KHHSSSSSAASSSSSHHK....
    ......KHHHSSSSSSSSSSHHHK....
    .......KHHKSSSSSSSSKHHK.....
    .......KKKKKSSSSSSKKKKK.....
    ..........KKWWWWWWKK........
    .....KKRRKWWWWWWWWWWKRRKK...
    ....KRRRKWWKWWWWWWKWWKRRRK..
    ...KRRRKRRRKKWWWWKKRRRKRRRK.
    ...KRRKRRGRRKKKKKKRRRRKRRRK.
    ..KRRRKRRRGRRRRRRRRRRRKRRRK.
    ..KRRRKRRRRGRRRRRRRRRRKRRRK.
    ..KRRSKRRRRRGRRRRRRRRRKSRRK.
    ..KRSSKRRRRRRGRRRRRRRRKSSRK.
    ..KRSSKRRRRRRRGRRRRRRRKSSRK.
    ..KRRKRRRRRRRRRGRRRRRRRKRRK.
    ..KRRKRRRRRRRRRRGRRRRRRKRRK.
    ..KKKKRRRRRRRRRRRGRRRRRKKKK.
    .....KRRRRRRRRRRRRGRRRK.....
    .....KRRRDRRRRRRRRRGRRK.....
    .....KRRRDRRRRRRRRRRGRK.....
    .....KRRRDDRRRRRRRRDDRK.....
    .....KRRRRRRRRRRRRRRRRK.....
    .....KKKKKKKKKKKKKKKKKK.....
    """)

    static func portrait(for rank: Rank) -> PixelSprite? {
        switch rank {
        case .jack: return jack
        case .queen: return queen
        case .king: return king
        default: return nil
        }
    }
}

// MARK: - Painter

enum PixelCardArt {
    /// Virtual grid width; unit = cardWidth / gridWidth. At the 1.45 card
    /// aspect ratio this yields an exact 40x58 pixel grid.
    static let gridWidth: CGFloat = 40

    struct SpritePlacement {
        let origin: CGPoint
        let unit: CGFloat
        var scale: CGFloat = 1
        var flipped = false
    }

    private static func placement(
        x horizontalPosition: CGFloat,
        y verticalPosition: CGFloat,
        unit: CGFloat,
        scale: CGFloat = 1,
        flipped: Bool = false
    ) -> SpritePlacement {
        SpritePlacement(
            origin: CGPoint(x: horizontalPosition, y: verticalPosition),
            unit: unit,
            scale: scale,
            flipped: flipped
        )
    }

    /// Draws a sprite whose origin is given in grid units. `scale` is an
    /// integer multiplier that keeps the art on the same pixel grid.
    static func draw(
        _ sprite: PixelSprite,
        in context: GraphicsContext,
        placement: SpritePlacement,
        color: (PixelInk) -> Color?
    ) {
        for row in 0..<sprite.height {
            let srcRow = placement.flipped ? sprite.height - 1 - row : row
            var col = 0
            while col < sprite.width {
                let srcCol = placement.flipped ? sprite.width - 1 - col : col
                let value = sprite.cells[srcRow][srcCol]
                guard value != 0, let ink = PixelInk(rawValue: value), let fill = color(ink) else {
                    col += 1
                    continue
                }
                var run = 1
                while col + run < sprite.width {
                    let nextCol = placement.flipped ? sprite.width - 1 - (col + run) : col + run
                    guard sprite.cells[srcRow][nextCol] == value else { break }
                    run += 1
                }
                let rect = CGRect(
                    x: (placement.origin.x + CGFloat(col) * placement.scale) * placement.unit,
                    y: (placement.origin.y + CGFloat(row) * placement.scale) * placement.unit,
                    width: CGFloat(run) * placement.scale * placement.unit,
                    height: placement.scale * placement.unit
                ).insetBy(dx: -0.2, dy: -0.2)
                context.fill(Path(rect), with: .color(fill))
                col += run
            }
        }
    }

    static func fillCells(
        _ context: GraphicsContext,
        gridRect: CGRect,
        unit: CGFloat,
        color: Color
    ) {
        let rect = CGRect(
            x: gridRect.origin.x * unit,
            y: gridRect.origin.y * unit,
            width: gridRect.width * unit,
            height: gridRect.height * unit
        )
            .insetBy(dx: -0.2, dy: -0.2)
        context.fill(Path(rect), with: .color(color))
    }

    // MARK: Front

    static func drawFront(card: Card, in context: GraphicsContext, size: CGSize, unit: CGFloat) {
        let gridH = size.height / unit
        let centerY = gridH / 2
        let ink = PixelPalette.suitColor(for: card.suit)
        let suitSprite = PixelSprites.suit(card.suit)

        let solid: (PixelInk) -> Color? = { pixelInk in
            switch pixelInk {
            case .ink, .inkHi: return ink
            default: return nil
            }
        }

        drawCornerIndices(card: card, in: context, gridHeight: gridH, unit: unit)

        if let portrait = PixelSprites.portrait(for: card.rank) {
            drawPortrait(portrait, card: card, in: context, centerY: centerY, unit: unit)
        } else if card.rank == .ace {
            let shaded: (PixelInk) -> Color? = { pixelInk in
                switch pixelInk {
                case .ink: return ink
                case .inkHi: return PixelPalette.suitHighlight(for: card.suit)
                default: return nil
                }
            }
            draw(
                suitSprite, in: context,
                placement: placement(x: (gridWidth - 14) / 2, y: centerY - 7, unit: unit, scale: 2),
                color: shaded
            )
        } else {
            let pipSprite = PixelSprites.pipSuit(card.suit)
            for pip in pipPlacements(count: card.rank.rawValue) {
                draw(
                    pipSprite, in: context,
                    placement: placement(
                        x: pip.originX,
                        y: centerY + pip.verticalOffset - 2.5,
                        unit: unit,
                        flipped: pip.verticalOffset > 0
                    ),
                    color: solid
                )
            }
        }
    }

    private static func drawCornerIndices(
        card: Card,
        in context: GraphicsContext,
        gridHeight: CGFloat,
        unit: CGFloat
    ) {
        let rankSprite = PixelSprites.rank(card.rank)
        let suitSprite = PixelSprites.suit(card.suit)
        let ink = PixelPalette.suitColor(for: card.suit)
        let solid: (PixelInk) -> Color? = { $0 == .ink || $0 == .inkHi ? ink : nil }
        draw(rankSprite, in: context, placement: placement(x: 3, y: 3, unit: unit), color: solid)
        draw(
            suitSprite,
            in: context,
            placement: placement(x: gridWidth - 10, y: 3, unit: unit),
            color: solid
        )
        draw(
            rankSprite,
            in: context,
            placement: placement(
                x: gridWidth - 3 - CGFloat(rankSprite.width),
                y: gridHeight - 10,
                unit: unit,
                flipped: true
            ),
            color: solid
        )
        draw(
            suitSprite,
            in: context,
            placement: placement(x: 3, y: gridHeight - 10, unit: unit, flipped: true),
            color: solid
        )
    }

    private static func drawPortrait(
        _ portrait: PixelSprite,
        card: Card,
        in context: GraphicsContext,
        centerY: CGFloat,
        unit: CGFloat
    ) {
        let isRed = card.suit.isRed
        let originX = (gridWidth - CGFloat(portrait.width)) / 2
        let originY = centerY - CGFloat(portrait.height) / 2

        let colors: [PixelInk: Color] = [
            .outlineDark: PixelPalette.outline,
            .skin: PixelPalette.skinTone,
            .skinShade: PixelPalette.skinShadow,
            .gold: PixelPalette.gold,
            .robe: isRed ? PixelPalette.robeRed : PixelPalette.robeBlue,
            .robeDark: isRed ? PixelPalette.robeRedDark : PixelPalette.robeBlueDark,
            .hair: PixelPalette.hair,
            .white: PixelPalette.ermine,
            .accent: PixelPalette.accent,
            .altRobe: isRed ? PixelPalette.robeBlue : PixelPalette.robeRed
        ]
        draw(
            portrait,
            in: context,
            placement: placement(x: originX, y: originY, unit: unit),
            color: { colors[$0] }
        )
    }

    // MARK: Pips

    struct PipPlacement {
        let originX: CGFloat
        let verticalOffset: CGFloat
    }

    private static let leftCol: CGFloat = 10.5
    private static let midCol: CGFloat = 17.5
    private static let rightCol: CGFloat = 24.5

    static func pipPlacements(count: Int) -> [PipPlacement] {
        func columns(_ verticalOffsets: [CGFloat]) -> [PipPlacement] {
            verticalOffsets.flatMap { verticalOffset in
                [
                    PipPlacement(originX: leftCol, verticalOffset: verticalOffset),
                    PipPlacement(originX: rightCol, verticalOffset: verticalOffset)
                ]
            }
        }
        func middle(_ verticalOffsets: [CGFloat]) -> [PipPlacement] {
            verticalOffsets.map { PipPlacement(originX: midCol, verticalOffset: $0) }
        }

        switch count {
        case 2: return middle([-10, 10])
        case 3: return middle([-12, 0, 12])
        case 4: return columns([-11, 11])
        case 5: return columns([-11, 11]) + middle([0])
        case 6: return columns([-11, 0, 11])
        case 7: return columns([-11, 0, 11]) + middle([-5.5])
        case 8: return columns([-12, -4, 4, 12])
        case 9: return columns([-12, -4, 4, 12]) + middle([0])
        case 10: return columns([-12, -4, 4, 12]) + middle([-8, 8])
        default: return []
        }
    }

}

// MARK: Back

extension PixelCardArt {

    /// Woven-lattice card back: a bright single-pixel frame around a diagonal
    /// weave in the colorway's muted tone with mid-tone intersections.
    static func drawBack(
        in context: GraphicsContext, size: CGSize, unit: CGFloat,
        colorway: PixelBackColorway = .navy
    ) {
        let gridH = size.height / unit
        let lastRow = Int(gridH.rounded(.down)) - 3

        drawBackFrame(in: context, gridHeight: gridH, unit: unit, color: colorway.bright)

        // Diagonal weave, phase-locked to the card center.
        let centerX = Int(gridWidth) / 2
        let centerYCell = Int((gridH / 2).rounded(.down))
        for row in 4...(lastRow - 1) {
            for column in 4...Int(gridWidth) - 5 {
                let sum = (column - centerX) + (row - centerYCell)
                let diff = (column - centerX) - (row - centerYCell)
                let onSum = ((sum % 6) + 6) % 6 == 0
                let onDiff = ((diff % 6) + 6) % 6 == 0
                if onSum && onDiff {
                    fillCells(
                        context,
                        gridRect: CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1),
                        unit: unit,
                        color: colorway.mid
                    )
                } else if onSum || onDiff {
                    fillCells(
                        context,
                        gridRect: CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1),
                        unit: unit,
                        color: colorway.muted
                    )
                }
            }
        }
    }

    private static func drawBackFrame(
        in context: GraphicsContext,
        gridHeight: CGFloat,
        unit: CGFloat,
        color: Color
    ) {
        let frameRects = [
            CGRect(x: 2, y: 2, width: gridWidth - 4, height: 1),
            CGRect(x: 2, y: gridHeight - 3, width: gridWidth - 4, height: 1),
            CGRect(x: 2, y: 3, width: 1, height: gridHeight - 6),
            CGRect(x: gridWidth - 3, y: 3, width: 1, height: gridHeight - 6)
        ]
        for gridRect in frameRects {
            fillCells(context, gridRect: gridRect, unit: unit, color: color)
        }
    }
}

// MARK: - Card Front

struct PixelCardFrontView: View {
    let card: Card
    let cardSize: CGSize
    let isSelected: Bool

    var body: some View {
        let unit = cardSize.width / PixelCardArt.gridWidth
        let shape = PixelCardShape(pixelSize: unit)
        let borderColor = isSelected ? Color.yellow.opacity(0.92) : PixelPalette.outline
        let borderWidth = isSelected ? max(2, unit * 1.6) : max(0.8, unit)

        ZStack {
            shape.fill(PixelPalette.cardFace, style: FillStyle(antialiased: false))
            Canvas { context, size in
                PixelCardArt.drawFront(card: card, in: context, size: size, unit: unit)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(shape, style: FillStyle(antialiased: false))
        .overlay(
            shape.strokeBorder(borderColor, lineWidth: borderWidth, antialiased: false)
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.24 : 0.10),
            radius: isSelected ? 7 : 2,
            x: 0,
            y: isSelected ? 4 : 1
        )
    }
}

// MARK: - Card Back

struct PixelCardBackView: View {
    let cardSize: CGSize
    let isSelected: Bool

    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id

    init(cardSize: CGSize, isSelected: Bool = false) {
        self.cardSize = cardSize
        self.isSelected = isSelected
    }

    var body: some View {
        let unit = cardSize.width / PixelCardArt.gridWidth
        let shape = PixelCardShape(pixelSize: unit)
        let borderColor = isSelected ? Color.yellow.opacity(0.88) : PixelPalette.outline
        let borderWidth = isSelected ? max(2, unit * 1.6) : max(0.8, unit)
        let colorway = PixelBackColorway.matching(.from(rawValue: cardBackColorRawValue))

        ZStack {
            shape.fill(colorway.deep, style: FillStyle(antialiased: false))
            Canvas { context, size in
                PixelCardArt.drawBack(in: context, size: size, unit: unit, colorway: colorway)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(shape, style: FillStyle(antialiased: false))
        .overlay(
            shape.strokeBorder(borderColor, lineWidth: borderWidth, antialiased: false)
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.24 : 0.12),
            radius: isSelected ? 7 : 2,
            x: 0,
            y: isSelected ? 4 : 1
        )
    }
}

// MARK: - Standalone Pixel Card Back

struct PixelStandaloneCardBackView: View {
    let cardSize: CGSize

    var body: some View {
        PixelCardBackView(cardSize: cardSize)
    }
}
