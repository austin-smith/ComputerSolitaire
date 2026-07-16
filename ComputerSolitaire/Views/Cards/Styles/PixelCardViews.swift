import SwiftUI

enum PixelCardStyle {
    static let info = CardStyleInfo(title: "Pixel", subtitle: "8-bit Retro")
}

// MARK: - Pixel Art Color Palette

enum PixelPalette {
    // Card face
    static let cardFace = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let cardFaceHighlight = Color(red: 1.00, green: 0.99, blue: 0.96)
    static let cardFaceShadow = Color(red: 0.82, green: 0.78, blue: 0.70)
    static let outline = Color(red: 0.13, green: 0.12, blue: 0.15)
    static let dropShadow = Color.black.opacity(0.32)
    static let selection = Color(red: 1.00, green: 0.78, blue: 0.16)

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

// MARK: - Pixel Grid

/// Converts virtual card cells into display-pixel-aligned rectangles. Card
/// widths are responsive, so a virtual cell is not always an integral number
/// of points; snapping both edges keeps every filled run crisp without gaps.
nonisolated struct PixelGrid {
    let unit: CGFloat
    let displayScale: CGFloat

    private var resolvedDisplayScale: CGFloat {
        max(1, displayScale)
    }

    var cellLength: CGFloat {
        max(1 / resolvedDisplayScale, snapped(unit))
    }

    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let minX = snapped(x * unit)
        let minY = snapped(y * unit)
        let maxX = snapped((x + width) * unit)
        let maxY = snapped((y + height) * unit)

        return CGRect(
            x: minX,
            y: minY,
            width: max(1 / resolvedDisplayScale, maxX - minX),
            height: max(1 / resolvedDisplayScale, maxY - minY)
        )
    }

    func snapped(_ value: CGFloat) -> CGFloat {
        (value * resolvedDisplayScale).rounded() / resolvedDisplayScale
    }
}

// MARK: - Card Silhouette (stepped pixel corners)

struct PixelCardShape: InsettableShape {
    /// One virtual pixel unit (card width / PixelCardArt.gridWidth).
    let px: CGFloat
    let displayScale: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let maxCorner = min(insetRect.width, insetRect.height) / 2
        let grid = PixelGrid(unit: px, displayScale: displayScale)
        let step = min(grid.cellLength, floor(maxCorner / 3))
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
        let w = lines.map(\.count).max() ?? 0
        cells = lines.map { line in
            var row = line.map { map[$0] ?? 0 }
            while row.count < w { row.append(0) }
            return row
        }
        width = w
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

    // Compact pip suits use an even 6x6 footprint so their origins and centers
    // stay on whole grid cells across the responsive card layout.
    static let spadePip = PixelSprite("""
    ..##..
    .####.
    ######
    ######
    ##..##
    ..##..
    """)

    static let heartPip = PixelSprite("""
    .##.##
    ######
    ######
    .####.
    ..##..
    ..##..
    """)

    static let diamondPip = PixelSprite("""
    ..##..
    .####.
    ######
    ######
    .####.
    ..##..
    """)

    static let clubPip = PixelSprite("""
    ..##..
    .####.
    ######
    ..##..
    .####.
    ..##..
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
    static let aceRank = PixelSprite("""
    .###.
    #...#
    #...#
    #####
    #...#
    #...#
    #...#
    """)

    static let ranks: [String: PixelSprite] = [
        "A": aceRank,
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
        ranks[rank.label] ?? aceRank
    }

    // Face card portraits — 28x35, outlined forms in the classic style.
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

enum PixelRoyalArtwork {
    static let logicalSize = CGSize(width: 26, height: 45)

    static func assetName(for rank: Rank) -> String? {
        switch rank {
        case .jack: "PixelJack"
        case .queen: "PixelQueen"
        case .king: "PixelKing"
        default: nil
        }
    }
}

// MARK: - Painter

enum PixelCardArt {
    /// Virtual grid width; unit = cardWidth / gridWidth. At the 1.45 card
    /// aspect ratio this yields an exact 40x58 pixel grid.
    static let gridWidth: CGFloat = 40

    /// Draws a sprite whose origin is given in grid units. `scale` is an
    /// integer multiplier that keeps the art on the same pixel grid.
    static func draw(
        _ sprite: PixelSprite,
        in context: GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        grid: PixelGrid,
        scale: CGFloat = 1,
        flipped: Bool = false,
        color: (PixelInk) -> Color?
    ) {
        for row in 0..<sprite.height {
            let srcRow = flipped ? sprite.height - 1 - row : row
            var col = 0
            while col < sprite.width {
                let srcCol = flipped ? sprite.width - 1 - col : col
                let value = sprite.cells[srcRow][srcCol]
                guard value != 0, let ink = PixelInk(rawValue: value), let fill = color(ink) else {
                    col += 1
                    continue
                }
                var run = 1
                while col + run < sprite.width {
                    let nextCol = flipped ? sprite.width - 1 - (col + run) : col + run
                    guard sprite.cells[srcRow][nextCol] == value else { break }
                    run += 1
                }
                let rect = grid.rect(
                    x: x + CGFloat(col) * scale,
                    y: y + CGFloat(row) * scale,
                    width: CGFloat(run) * scale,
                    height: scale
                )
                context.fill(Path(rect), with: .color(fill))
                col += run
            }
        }
    }

    static func fillCells(
        _ context: GraphicsContext,
        x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
        grid: PixelGrid,
        color: Color
    ) {
        let rect = grid.rect(x: x, y: y, width: w, height: h)
        context.fill(Path(rect), with: .color(color))
    }

    // MARK: Front

    static func drawFront(card: Card, in context: GraphicsContext, size: CGSize, grid: PixelGrid) {
        let gridH = size.height / grid.unit
        let centerY = gridH / 2
        let ink = PixelPalette.suitColor(for: card.suit)
        let suitSprite = PixelSprites.suit(card.suit)
        let rankSprite = PixelSprites.rank(card.rank)

        let solid: (PixelInk) -> Color? = { pixelInk in
            switch pixelInk {
            case .ink, .inkHi: return ink
            default: return nil
            }
        }

        drawFaceBevel(in: context, gridHeight: gridH, grid: grid)

        // Corner indices: rank top-left / suit top-right, mirrored below.
        draw(rankSprite, in: context, x: 3, y: 3, grid: grid, color: solid)
        draw(suitSprite, in: context, x: gridWidth - 3 - 7, y: 3, grid: grid, color: solid)
        draw(
            rankSprite, in: context,
            x: gridWidth - 3 - CGFloat(rankSprite.width), y: gridH - 3 - 7,
            grid: grid, flipped: true, color: solid
        )
        draw(suitSprite, in: context, x: 3, y: gridH - 3 - 7, grid: grid, flipped: true, color: solid)

        if card.rank == .ace {
            let shaded: (PixelInk) -> Color? = { pixelInk in
                switch pixelInk {
                case .ink: return ink
                case .inkHi: return PixelPalette.suitHighlight(for: card.suit)
                default: return nil
                }
            }
            draw(
                suitSprite, in: context,
                x: (gridWidth - 14) / 2, y: centerY - 7,
                grid: grid, scale: 2, color: shaded
            )
        } else if card.rank.rawValue < Rank.jack.rawValue {
            let pipSprite = PixelSprites.pipSuit(card.suit)
            for pip in pipPlacements(count: card.rank.rawValue) {
                draw(
                    pipSprite, in: context,
                    x: pip.x,
                    y: centerY + pip.dy - CGFloat(pipSprite.height / 2),
                    grid: grid,
                    flipped: pip.dy > 0,
                    color: solid
                )
            }
        }
    }

    private static func drawFaceBevel(
        in context: GraphicsContext,
        gridHeight: CGFloat,
        grid: PixelGrid
    ) {
        fillCells(
            context, x: 4, y: 2, w: gridWidth - 8, h: 1,
            grid: grid, color: PixelPalette.cardFaceHighlight
        )
        fillCells(
            context, x: 2, y: 4, w: 1, h: gridHeight - 8,
            grid: grid, color: PixelPalette.cardFaceHighlight
        )
        fillCells(
            context, x: 4, y: gridHeight - 3, w: gridWidth - 8, h: 1,
            grid: grid, color: PixelPalette.cardFaceShadow
        )
        fillCells(
            context, x: gridWidth - 3, y: 4, w: 1, h: gridHeight - 8,
            grid: grid, color: PixelPalette.cardFaceShadow
        )
    }

    private static func drawPortrait(
        _ portrait: PixelSprite,
        card: Card,
        in context: GraphicsContext,
        centerY: CGFloat,
        grid: PixelGrid
    ) {
        let isRed = card.suit.isRed
        let originX = (gridWidth - CGFloat(portrait.width)) / 2
        let originY = centerY - CGFloat(portrait.height) / 2

        draw(portrait, in: context, x: originX, y: originY, grid: grid) { pixelInk in
            switch pixelInk {
            case .outlineDark: return PixelPalette.outline
            case .skin: return PixelPalette.skinTone
            case .skinShade: return PixelPalette.skinShadow
            case .gold: return PixelPalette.gold
            case .robe: return isRed ? PixelPalette.robeRed : PixelPalette.robeBlue
            case .robeDark: return isRed ? PixelPalette.robeRedDark : PixelPalette.robeBlueDark
            case .hair: return PixelPalette.hair
            case .white: return PixelPalette.ermine
            case .accent: return PixelPalette.accent
            case .altRobe: return isRed ? PixelPalette.robeBlue : PixelPalette.robeRed
            case .ink, .inkHi, .none: return nil
            }
        }
    }

    // MARK: Pips

    struct PipPlacement {
        let x: CGFloat  // sprite origin column
        let dy: CGFloat // sprite center offset from card center
    }

    private static let leftCol: CGFloat = 10
    private static let midCol: CGFloat = 17
    private static let rightCol: CGFloat = 24

    static func pipPlacements(count: Int) -> [PipPlacement] {
        func cols(_ dys: [CGFloat]) -> [PipPlacement] {
            dys.flatMap { dy in
                [PipPlacement(x: leftCol, dy: dy), PipPlacement(x: rightCol, dy: dy)]
            }
        }
        func mid(_ dys: [CGFloat]) -> [PipPlacement] {
            dys.map { PipPlacement(x: midCol, dy: $0) }
        }

        switch count {
        case 2: return mid([-10, 10])
        case 3: return mid([-12, 0, 12])
        case 4: return cols([-11, 11])
        case 5: return cols([-11, 11]) + mid([0])
        case 6: return cols([-11, 0, 11])
        case 7: return cols([-11, 0, 11]) + mid([-6])
        case 8: return cols([-12, -4, 4, 12])
        case 9: return cols([-12, -4, 4, 12]) + mid([0])
        case 10: return cols([-12, -4, 4, 12]) + mid([-8, 8])
        default: return []
        }
    }

    // MARK: Back

    /// Woven-lattice card back: a bright single-pixel frame around a diagonal
    /// weave in the colorway's muted tone with mid-tone intersections.
    static func drawBack(
        in context: GraphicsContext, size: CGSize, grid: PixelGrid,
        colorway: PixelBackColorway = .navy
    ) {
        let gridH = size.height / grid.unit
        let lastRow = Int(gridH.rounded(.down)) - 3

        // Inner bright frame, one unit thick, inset 2 from the edge.
        let frame = colorway.bright
        fillCells(context, x: 2, y: 2, w: gridWidth - 4, h: 1, grid: grid, color: frame)
        fillCells(context, x: 2, y: gridH - 3, w: gridWidth - 4, h: 1, grid: grid, color: frame)
        fillCells(context, x: 2, y: 3, w: 1, h: gridH - 6, grid: grid, color: frame)
        fillCells(context, x: gridWidth - 3, y: 3, w: 1, h: gridH - 6, grid: grid, color: frame)

        // Diagonal weave, phase-locked to the card center.
        let centerX = Int(gridWidth) / 2
        let centerYCell = Int((gridH / 2).rounded(.down))
        for cy in 4...(lastRow - 1) {
            for cx in 4...Int(gridWidth) - 5 {
                let sum = (cx - centerX) + (cy - centerYCell)
                let diff = (cx - centerX) - (cy - centerYCell)
                let onSum = ((sum % 6) + 6) % 6 == 0
                let onDiff = ((diff % 6) + 6) % 6 == 0
                if onSum && onDiff {
                    fillCells(
                        context, x: CGFloat(cx), y: CGFloat(cy), w: 1, h: 1,
                        grid: grid, color: colorway.mid
                    )
                } else if onSum || onDiff {
                    fillCells(
                        context, x: CGFloat(cx), y: CGFloat(cy), w: 1, h: 1,
                        grid: grid, color: colorway.muted
                    )
                }
            }
        }

        drawBackMedallion(in: context, gridHeight: gridH, grid: grid, colorway: colorway)
    }

    private static func drawBackMedallion(
        in context: GraphicsContext,
        gridHeight: CGFloat,
        grid: PixelGrid,
        colorway: PixelBackColorway
    ) {
        let originX: CGFloat = 11
        let originY = (gridHeight - 24) / 2

        fillCells(context, x: originX, y: originY, w: 18, h: 24, grid: grid, color: colorway.deep)
        fillCells(context, x: originX, y: originY, w: 18, h: 1, grid: grid, color: colorway.bright)
        fillCells(context, x: originX, y: originY + 23, w: 18, h: 1, grid: grid, color: colorway.bright)
        fillCells(context, x: originX, y: originY + 1, w: 1, h: 22, grid: grid, color: colorway.bright)
        fillCells(context, x: originX + 17, y: originY + 1, w: 1, h: 22, grid: grid, color: colorway.bright)

        let brightInk: (PixelInk) -> Color? = { ink in
            ink == .none ? nil : colorway.bright
        }
        let mutedInk: (PixelInk) -> Color? = { ink in
            ink == .none ? nil : colorway.muted
        }

        draw(PixelSprites.spadePip, in: context, x: 13, y: originY + 4, grid: grid, color: brightInk)
        draw(PixelSprites.heartPip, in: context, x: 21, y: originY + 4, grid: grid, color: mutedInk)
        draw(PixelSprites.diamondPip, in: context, x: 13, y: originY + 14, grid: grid, color: mutedInk)
        draw(PixelSprites.clubPip, in: context, x: 21, y: originY + 14, grid: grid, color: brightInk)
    }
}

// MARK: - Card Surface

private struct PixelCardSurface<Content: View>: View {
    let cardSize: CGSize
    let displayScale: CGFloat
    let fill: Color
    let isSelected: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let unit = cardSize.width / PixelCardArt.gridWidth
        let grid = PixelGrid(unit: unit, displayScale: displayScale)
        let shape = PixelCardShape(px: unit, displayScale: displayScale)
        let borderWidth = isSelected ? grid.cellLength * 2 : grid.cellLength
        let shadowOffset = grid.cellLength * (isSelected ? 2 : 1)

        ZStack {
            shape
                .fill(PixelPalette.dropShadow, style: FillStyle(antialiased: false))
                .offset(x: shadowOffset, y: shadowOffset)

            ZStack {
                shape.fill(fill, style: FillStyle(antialiased: false))
                content
            }
            .clipShape(shape, style: FillStyle(antialiased: false))
            .overlay {
                shape.strokeBorder(
                    isSelected ? PixelPalette.selection : PixelPalette.outline,
                    lineWidth: borderWidth,
                    antialiased: false
                )
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }
}

// MARK: - Card Front

struct PixelCardFrontView: View {
    let card: Card
    let cardSize: CGSize
    let isSelected: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let unit = cardSize.width / PixelCardArt.gridWidth
        let grid = PixelGrid(unit: unit, displayScale: displayScale)

        PixelCardSurface(
            cardSize: cardSize,
            displayScale: displayScale,
            fill: PixelPalette.cardFace,
            isSelected: isSelected
        ) {
            ZStack {
                Canvas { context, size in
                    PixelCardArt.drawFront(card: card, in: context, size: size, grid: grid)
                }

                if let royalAssetName = PixelRoyalArtwork.assetName(for: card.rank) {
                    Image(royalAssetName)
                        .resizable()
                        .interpolation(.none)
                        .frame(
                            width: PixelRoyalArtwork.logicalSize.width * unit,
                            height: PixelRoyalArtwork.logicalSize.height * unit
                        )
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Card Back

struct PixelCardBackView: View {
    let cardSize: CGSize
    let isSelected: Bool

    @AppStorage(SettingsKey.cardBackColor) private var cardBackColorRawValue = CardBackColor.defaultValue.id
    @Environment(\.displayScale) private var displayScale

    init(cardSize: CGSize, isSelected: Bool = false) {
        self.cardSize = cardSize
        self.isSelected = isSelected
    }

    var body: some View {
        let unit = cardSize.width / PixelCardArt.gridWidth
        let grid = PixelGrid(unit: unit, displayScale: displayScale)
        let colorway = PixelBackColorway.matching(.from(rawValue: cardBackColorRawValue))

        PixelCardSurface(
            cardSize: cardSize,
            displayScale: displayScale,
            fill: colorway.deep,
            isSelected: isSelected
        ) {
            Canvas { context, size in
                PixelCardArt.drawBack(in: context, size: size, grid: grid, colorway: colorway)
            }
        }
    }
}

// MARK: - Standalone Pixel Card Back

struct PixelStandaloneCardBackView: View {
    let cardSize: CGSize

    var body: some View {
        PixelCardBackView(cardSize: cardSize)
    }
}

#Preview("Pixel Deck") {
    let cardSize = CGSize(width: 80, height: 116)
    let cards = [
        Card(suit: .spades, rank: .ace, isFaceUp: true),
        Card(suit: .hearts, rank: .seven, isFaceUp: true),
        Card(suit: .clubs, rank: .ten, isFaceUp: true),
        Card(suit: .diamonds, rank: .jack, isFaceUp: true),
        Card(suit: .hearts, rank: .queen, isFaceUp: true),
        Card(suit: .spades, rank: .king, isFaceUp: true),
    ]

    VStack(spacing: 20) {
        HStack(spacing: 12) {
            ForEach(cards.prefix(3)) { card in
                PixelCardFrontView(card: card, cardSize: cardSize, isSelected: false)
            }
        }
        HStack(spacing: 12) {
            ForEach(cards.suffix(3)) { card in
                PixelCardFrontView(card: card, cardSize: cardSize, isSelected: false)
            }
            PixelCardBackView(cardSize: cardSize)
        }
    }
    .padding(28)
    .background(Color(red: 0.16, green: 0.38, blue: 0.32))
}
