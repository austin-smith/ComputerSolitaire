import SwiftUI

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

    // Card back
    static let backDeep = Color(red: 0.11, green: 0.16, blue: 0.37)
    static let backMid = Color(red: 0.21, green: 0.29, blue: 0.56)
    static let backBright = Color(red: 0.55, green: 0.64, blue: 0.90)
    static let backGold = Color(red: 0.85, green: 0.68, blue: 0.25)

    static func suitColor(for suit: Suit) -> Color {
        suit.isRed ? red : black
    }

    static func suitHighlight(for suit: Suit) -> Color {
        suit.isRed ? redLight : blackLight
    }
}

// MARK: - Card Silhouette (stepped pixel corners)

struct PixelCardShape: InsettableShape {
    /// One virtual pixel unit (card width / PixelCardArt.gridWidth).
    let px: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let maxCorner = min(insetRect.width, insetRect.height) / 2
        let step = max(1, min(px, floor(maxCorner / 3)))
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
            "G": 6, "R": 7, "D": 8, "H": 9, "W": 10, "A": 11, "B": 12,
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
        """),
    ]

    static func rank(_ rank: Rank) -> PixelSprite {
        ranks[rank.label] ?? ranks["A"]!
    }

    // Face card busts — 18x22.
    static let king = PixelSprite("""
    ....G..G..G..G....
    ...GGGGGGGGGGGG...
    ...GGAGGAAGGAGG...
    ...GGGGGGGGGGGG...
    ...HHHHHHHHHHHH...
    ...HSSSSSSSSSSH...
    ...HSSKSSSSKSSH...
    ...HSSSSssSSSSH...
    ...HSHHHSSHHHSH...
    ...HHHHHAAHHHHH...
    ...HHHHHHHHHHHH...
    ....HHHHHHHHHH....
    ..RR.HHHHHHHH.RR..
    .RRRR.HHHHHH.RRRR.
    .RRRRWWHHHHWWRRRR.
    DRRRRRGWWWWGRRRRRD
    DRRRRRRGWWGRRRRRRD
    DRRRRRRRGGRRRRRRRD
    DRRRRRRRRRRRRRRRRD
    DRRRRRRRRRRRRRRRRD
    DDRRRRRRRRRRRRRRDD
    DDDDDDDDDDDDDDDDDD
    """)

    static let queen = PixelSprite("""
    ....G..G..G..G....
    ....GGGGGGGGGG....
    ...HHHHHHHHHHHH...
    ..HHSSSSSSSSSSHH..
    ..HHSSKSSSSKSSHH..
    ..HHSSSSssSSSSHH..
    ..HHSSSSAASSSSHH..
    ..HHSSSSSSSSSSHH..
    ..HHHSSSSSSSSHHH..
    ..HHH.SSSSSS.HHH..
    ..HHH.SGGGGS.HHH..
    ..HHRRRRRRRRRRHH..
    .HHRRRRRRRRRRRRHH.
    .HHRRRRRGGRRRRRHH.
    .HRRRRRRRRRRRRRRH.
    DRRRRRRRWWRRRRRRRD
    DRRRRRRWWWWRRRRRRD
    DRRRRRWWWWWWRRRRRD
    DRRRRRWWWWWWRRRRRD
    DRRRRWWWWWWWWRRRRD
    DDRRRWWWWWWWWRRRDD
    DDDDDDDDDDDDDDDDDD
    """)

    static let jack = PixelSprite("""
    ...........GA.....
    ....BBBBBB.GA.....
    ...BBBBBBBBBG.....
    ..BBBBBBBBBBBB....
    ...HHHHHHHHHHH....
    ...HSSSSSSSSSSH...
    ...HSSKSSSSKSSH...
    ...HSSSSssSSSSH...
    ...HSSSSAASSSSH...
    ....SSSSSSSSSS....
    ......SSSSSS......
    ....WWWWWWWWWW....
    ..RRRWWRRRRWWRRR..
    .RRRRGRRRRRRRRRRR.
    .RRRRRGRRRRRRRRRR.
    DRRRRRRGRRRRRRRRRD
    DRRRRRRRGRRRRRRRRD
    DRRRRRRRRGRRRRRRRD
    DRRRRRRRRRGRRRRRRD
    DRRRRRRRRRRGRRRRRD
    DDRRRRRRRRRRRRRRDD
    DDDDDDDDDDDDDDDDDD
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

    /// Draws a sprite whose origin is given in grid units. `scale` is an
    /// integer multiplier that keeps the art on the same pixel grid.
    static func draw(
        _ sprite: PixelSprite,
        in context: GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        unit: CGFloat,
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
                let rect = CGRect(
                    x: (x + CGFloat(col) * scale) * unit,
                    y: (y + CGFloat(row) * scale) * unit,
                    width: CGFloat(run) * scale * unit,
                    height: scale * unit
                ).insetBy(dx: -0.2, dy: -0.2)
                context.fill(Path(rect), with: .color(fill))
                col += run
            }
        }
    }

    static func fillCells(
        _ context: GraphicsContext,
        x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
        unit: CGFloat,
        color: Color
    ) {
        let rect = CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)
            .insetBy(dx: -0.2, dy: -0.2)
        context.fill(Path(rect), with: .color(color))
    }

    // MARK: Front

    static func drawFront(card: Card, in context: GraphicsContext, size: CGSize, unit: CGFloat) {
        let gridH = size.height / unit
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

        // Corner indices: rank top-left / suit top-right, mirrored below.
        draw(rankSprite, in: context, x: 3, y: 3, unit: unit, color: solid)
        draw(suitSprite, in: context, x: gridWidth - 3 - 7, y: 3, unit: unit, color: solid)
        draw(
            rankSprite, in: context,
            x: gridWidth - 3 - CGFloat(rankSprite.width), y: gridH - 3 - 7,
            unit: unit, flipped: true, color: solid
        )
        draw(suitSprite, in: context, x: 3, y: gridH - 3 - 7, unit: unit, flipped: true, color: solid)

        if let portrait = PixelSprites.portrait(for: card.rank) {
            drawPortraitPanel(portrait, card: card, in: context, centerY: centerY, unit: unit)
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
                x: (gridWidth - 14) / 2, y: centerY - 7,
                unit: unit, scale: 2, color: shaded
            )
        } else {
            let pipSprite = PixelSprites.pipSuit(card.suit)
            for pip in pipPlacements(count: card.rank.rawValue) {
                draw(
                    pipSprite, in: context,
                    x: pip.x, y: centerY + pip.dy - 2.5,
                    unit: unit, flipped: pip.dy > 0, color: solid
                )
            }
        }
    }

    private static func drawPortraitPanel(
        _ portrait: PixelSprite,
        card: Card,
        in context: GraphicsContext,
        centerY: CGFloat,
        unit: CGFloat
    ) {
        let ink = PixelPalette.suitColor(for: card.suit)
        let isRed = card.suit.isRed
        let panelX: CGFloat = 9
        let panelW: CGFloat = 22
        let panelTop = centerY - 13
        let panelBottom = centerY + 12

        // Frame
        fillCells(context, x: panelX, y: panelTop, w: panelW, h: 1, unit: unit, color: ink)
        fillCells(context, x: panelX, y: panelBottom, w: panelW, h: 1, unit: unit, color: ink)
        fillCells(context, x: panelX, y: panelTop + 1, w: 1, h: 24, unit: unit, color: ink)
        fillCells(context, x: panelX + panelW - 1, y: panelTop + 1, w: 1, h: 24, unit: unit, color: ink)
        for (cx, cy) in [
            (panelX, panelTop), (panelX + panelW - 1, panelTop),
            (panelX, panelBottom), (panelX + panelW - 1, panelBottom),
        ] {
            fillCells(context, x: cx, y: cy, w: 1, h: 1, unit: unit, color: PixelPalette.gold)
        }

        draw(portrait, in: context, x: 11, y: centerY - 11, unit: unit) { pixelInk in
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

    private static let leftCol: CGFloat = 10.5
    private static let midCol: CGFloat = 17.5
    private static let rightCol: CGFloat = 24.5

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
        case 7: return cols([-11, 0, 11]) + mid([-5.5])
        case 8: return cols([-12, -4, 4, 12])
        case 9: return cols([-12, -4, 4, 12]) + mid([0])
        case 10: return cols([-12, -4, 4, 12]) + mid([-8, 8])
        default: return []
        }
    }

    // MARK: Back

    static func drawBack(in context: GraphicsContext, size: CGSize, unit: CGFloat) {
        let gridH = size.height / unit
        let lastRow = Int(gridH.rounded(.down)) - 3

        // Inner bright frame, one unit thick, inset 2 from the edge.
        let frame = PixelPalette.backBright
        fillCells(context, x: 2, y: 2, w: gridWidth - 4, h: 1, unit: unit, color: frame)
        fillCells(context, x: 2, y: gridH - 3, w: gridWidth - 4, h: 1, unit: unit, color: frame)
        fillCells(context, x: 2, y: 3, w: 1, h: gridH - 6, unit: unit, color: frame)
        fillCells(context, x: gridWidth - 3, y: 3, w: 1, h: gridH - 6, unit: unit, color: frame)

        // Diamond trellis field, phase-locked to the card center.
        let centerX = Int(gridWidth) / 2
        let centerYCell = Int((gridH / 2).rounded(.down))
        for cy in 4...(lastRow - 1) {
            for cx in 4...Int(gridWidth) - 5 {
                let sum = (cx - centerX) + (cy - centerYCell)
                let diff = (cx - centerX) - (cy - centerYCell)
                let onSum = sum % 6 == 0
                let onDiff = diff % 6 == 0
                if onSum && onDiff {
                    fillCells(
                        context, x: CGFloat(cx), y: CGFloat(cy), w: 1, h: 1,
                        unit: unit, color: PixelPalette.backGold
                    )
                } else if onSum || onDiff {
                    fillCells(
                        context, x: CGFloat(cx), y: CGFloat(cy), w: 1, h: 1,
                        unit: unit, color: PixelPalette.backMid
                    )
                }
            }
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
        let shape = PixelCardShape(px: unit)
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

    init(cardSize: CGSize, isSelected: Bool = false) {
        self.cardSize = cardSize
        self.isSelected = isSelected
    }

    var body: some View {
        let unit = cardSize.width / PixelCardArt.gridWidth
        let shape = PixelCardShape(px: unit)
        let borderColor = isSelected ? Color.yellow.opacity(0.88) : PixelPalette.outline
        let borderWidth = isSelected ? max(2, unit * 1.6) : max(0.8, unit)

        ZStack {
            shape.fill(PixelPalette.backDeep, style: FillStyle(antialiased: false))
            Canvas { context, size in
                PixelCardArt.drawBack(in: context, size: size, unit: unit)
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
