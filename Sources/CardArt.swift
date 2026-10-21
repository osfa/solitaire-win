import Foundation

/// Pixel-art deck at the original 71×96 card size. Atlas rows: spades, hearts, clubs, diamonds, backs.
enum CardArt {
    static let cardW = 71
    static let cardH = 96
    static let columns = 13
    static let rows = 5
    static let atlasW = cardW * columns
    static let atlasH = cardH * rows
    static let backCard = 52

    struct Color { var r, g, b: UInt8; var a: UInt8 = 255 }
    static let white = Color(r: 255, g: 255, b: 255)
    static let black = Color(r: 0, g: 0, b: 0)
    static let red = Color(r: 255, g: 0, b: 0)
    static let blue = Color(r: 0, g: 0, b: 255)
    static let navy = Color(r: 0, g: 0, b: 128)
    static let yellow = Color(r: 255, g: 255, b: 0)
    static let clear = Color(r: 0, g: 0, b: 0, a: 0)

    typealias Glyph = [[Bool]]

    static func glyph(_ rows: [String]) -> Glyph { rows.map { $0.map { $0 == "X" } } }

    struct Sprite {
        let w: Int, h: Int
        var px: [Color]

        init(w: Int, h: Int, fill: Color) {
            self.w = w
            self.h = h
            px = Array(repeating: fill, count: w * h)
        }

        mutating func set(_ x: Int, _ y: Int, _ c: Color) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            px[y * w + x] = c
        }

        /// Inclusive corners.
        mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Color) {
            guard x1 >= x0, y1 >= y0 else { return }
            for y in y0...y1 { for x in x0...x1 { set(x, y, c) } }
        }

        mutating func glyph(_ g: Glyph, _ x: Int, _ y: Int, _ c: Color, rotated: Bool = false, scale: Int = 1) {
            let gh = g.count
            for (gy, row) in g.enumerated() {
                for (gx, on) in row.enumerated() where on {
                    let sx = rotated ? row.count - 1 - gx : gx
                    let sy = rotated ? gh - 1 - gy : gy
                    rect(x + sx * scale, y + sy * scale, x + sx * scale + scale - 1, y + sy * scale + scale - 1, c)
                }
            }
        }

        mutating func blit(_ s: Sprite, _ x: Int, _ y: Int, rotated: Bool = false) {
            for sy in 0..<s.h {
                for sx in 0..<s.w {
                    let c = s.px[sy * s.w + sx]
                    guard c.a > 0 else { continue }
                    if rotated { set(x + s.w - 1 - sx, y + s.h - 1 - sy, c) } else { set(x + sx, y + sy, c) }
                }
            }
        }
    }

    // MARK: Glyphs

    static let pips: [Glyph] = [
        glyph(["...X...", "..XXX..", ".XXXXX.", "XXXXXXX", "XXXXXXX", ".X.X.X.", "...X...", "..XXX.."]),
        glyph([".XX.XX.", "XXXXXXX", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]),
        glyph(["..XXX..", "..XXX..", "XX.X.XX", "XXXXXXX", "XX.X.XX", "...X...", "..XXX.."]),
        glyph(["...X...", "..XXX..", ".XXXXX.", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]),
    ]

    static let smallSuits: [Glyph] = [
        glyph(["..X..", ".XXX.", "XXXXX", "XXXXX", "..X.."]),
        glyph(["XX.XX", "XXXXX", "XXXXX", ".XXX.", "..X.."]),
        glyph(["..X..", ".XXX.", "X.X.X", "XXXXX", "..X.."]),
        glyph(["..X..", ".XXX.", "XXXXX", ".XXX.", "..X.."]),
    ]

    static let rankGlyphs: [Glyph] = [
        glyph([".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"]),
        glyph([".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"]),
        glyph(["XXXX.", "....X", "....X", ".XXX.", "....X", "....X", "XXXX."]),
        glyph(["...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."]),
        glyph(["XXXXX", "X....", "XXXX.", "....X", "....X", "X...X", ".XXX."]),
        glyph(["..XX.", ".X...", "X....", "XXXX.", "X...X", "X...X", ".XXX."]),
        glyph(["XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."]),
        glyph([".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."]),
        glyph([".XXX.", "X...X", "X...X", ".XXXX", "....X", "...X.", ".XX.."]),
        glyph([".X...XXX.", "XX..X...X", ".X..X..XX", ".X..X.X.X", ".X..XX..X", ".X..X...X", "XXX..XXX."]),
        glyph(["..XXX", "...X.", "...X.", "...X.", "...X.", "X..X.", ".XX.."]),
        glyph([".XXX.", "X...X", "X...X", "X...X", "X.X.X", "X..X.", ".XX.X"]),
        glyph(["X...X", "X..X.", "X.X..", "XX...", "X.X..", "X..X.", "X...X"]),
    ]

    /// Pip spots for 2…10: (column −1/0/1, fraction from top row to bottom row).
    static let pipLayout: [[(Int, Double)]] = [
        [(0, 0), (0, 1)],
        [(0, 0), (0, 0.5), (0, 1)],
        [(-1, 0), (1, 0), (-1, 1), (1, 1)],
        [(-1, 0), (1, 0), (0, 0.5), (-1, 1), (1, 1)],
        [(-1, 0), (1, 0), (-1, 0.5), (1, 0.5), (-1, 1), (1, 1)],
        [(-1, 0), (1, 0), (0, 0.25), (-1, 0.5), (1, 0.5), (-1, 1), (1, 1)],
        [(-1, 0), (1, 0), (0, 0.25), (-1, 0.5), (1, 0.5), (0, 0.75), (-1, 1), (1, 1)],
        [(-1, 0), (1, 0), (-1, 1.0 / 3), (1, 1.0 / 3), (0, 0.5), (-1, 2.0 / 3), (1, 2.0 / 3), (-1, 1), (1, 1)],
        [(-1, 0), (1, 0), (0, 1.0 / 6), (-1, 1.0 / 3), (1, 1.0 / 3), (-1, 2.0 / 3), (1, 2.0 / 3), (0, 5.0 / 6), (-1, 1), (1, 1)],
    ]

    // MARK: Atlas

    /// RGBA8, row-major, atlasW × atlasH.
    static func makeAtlas() -> [UInt8] {
        var atlas = Sprite(w: atlasW, h: atlasH, fill: clear)
        for suit in 0..<4 {
            for rank in 0..<13 { atlas.blit(face(suit: suit, rank: rank), rank * cardW, suit * cardH) }
        }
        for i in 0..<columns { atlas.blit(back(variant: i), i * cardW, 4 * cardH) }
        var bytes = [UInt8]()
        bytes.reserveCapacity(atlasW * atlasH * 4)
        for c in atlas.px { bytes += [c.r, c.g, c.b, c.a] }
        return bytes
    }

    static func blank() -> Sprite {
        var s = Sprite(w: cardW, h: cardH, fill: white)
        s.rect(1, 0, cardW - 2, 0, black)
        s.rect(1, cardH - 1, cardW - 2, cardH - 1, black)
        s.rect(0, 1, 0, cardH - 2, black)
        s.rect(cardW - 1, 1, cardW - 1, cardH - 2, black)
        for (x, y) in [(0, 0), (cardW - 1, 0), (0, cardH - 1), (cardW - 1, cardH - 1)] { s.set(x, y, clear) }
        return s
    }

    static func face(suit: Int, rank: Int) -> Sprite {
        var s = blank()
        let ink = suit == 1 || suit == 3 ? red : black
        let rg = rankGlyphs[rank]
        s.glyph(rg, 3, 3, ink)
        s.glyph(rg, cardW - 3 - rg[0].count, cardH - 3 - rg.count, ink, rotated: true)
        let sm = smallSuits[suit]
        s.glyph(sm, 3, 12, ink)
        s.glyph(sm, cardW - 3 - 5, cardH - 12 - 5, ink, rotated: true)

        let pip = pips[suit]
        switch rank {
        case 0:
            s.glyph(pip, 35 - 10, 48 - pip.count * 3 / 2, ink, scale: 3)
        case 1...9:
            for (col, f) in pipLayout[rank - 1] {
                let cx = 35 + col * 13
                let cy = 17 + Int((f * 61).rounded())
                s.glyph(pip, cx - 3, cy - pip.count / 2, ink, rotated: f > 0.5)
            }
        default:
            let half = courtHalf(suit: suit, rank: rank, ink: ink)
            s.blit(half, 13, 12)
            s.blit(half, 13, 12 + half.h, rotated: true)
            s.rect(13, 12, 57, 12, black)
            s.rect(13, 83, 57, 83, black)
            s.rect(13, 12, 13, 83, black)
            s.rect(57, 12, 57, 83, black)
        }
        return s
    }

    /// Top half of a court figure, 45×36; the card shows it twice, the second turned 180°.
    static func courtHalf(suit: Int, rank: Int, ink: Color) -> Sprite {
        var s = Sprite(w: 45, h: 36, fill: white)
        let (robeA, robeB) = rank == 12 ? (red, blue) : rank == 11 ? (blue, red) : (yellow, red)

        // Robe
        for y in 21...35 {
            let hw = 8 + (y - 21) * 12 / 14
            for x in (22 - hw)...(22 + hw) {
                var c = x < 21 ? robeA : x > 23 ? robeB : yellow
                if x < 21, (x + y) % 4 == 0 { c = black }
                if x > 23, (x - y + 40) % 4 == 0 { c = black }
                s.set(x, y, c)
            }
        }
        s.rect(15, 20, 29, 21, yellow)
        s.rect(15, 21, 29, 21, black)

        // Face
        s.rect(17, 9, 27, 19, white)
        s.rect(16, 10, 16, 18, black)
        s.rect(28, 10, 28, 18, black)
        s.rect(17, 19, 27, 19, black)
        for x in [19, 20, 24, 25] { s.set(x, 12, black) }
        s.rect(22, 13, 22, 15, black)
        s.rect(20, 17, 24, 17, red)

        switch rank {
        case 12: // King: crown, beard, sword
            s.rect(15, 5, 29, 8, yellow)
            for cx in [15, 22, 29] {
                s.rect(cx - 1, 3, cx + 1, 4, yellow)
                s.set(cx, 2, yellow)
            }
            s.set(18, 6, black); s.set(26, 6, black); s.set(22, 6, red)
            for y in 17...20 { for x in 17...27 where (x + y) % 2 == 0 { s.set(x, y, yellow) } }
            s.rect(37, 6, 37, 35, black)
            s.rect(35, 24, 39, 24, yellow)
        case 11: // Queen: small crown, long hair, flower
            s.rect(16, 6, 28, 8, yellow)
            for x in stride(from: 16, through: 28, by: 3) { s.set(x, 5, yellow) }
            s.rect(13, 9, 15, 22, yellow)
            s.rect(29, 9, 31, 22, yellow)
            s.rect(7, 22, 9, 24, red)
            s.set(8, 23, yellow)
            s.rect(8, 25, 8, 35, black)
        default: // Jack: cap with feather, halberd
            s.rect(15, 5, 29, 8, red)
            for i in 0...6 { s.set(29 + i, 5 - i * 5 / 6, yellow) }
            s.rect(7, 4, 7, 35, black)
            for y in 4...9 { s.rect(7 - (9 - y) / 2, y, 7 + (y - 4), y, yellow) }
        }

        s.glyph(smallSuits[suit], 2, 2, ink)
        return s
    }

    static func back(variant: Int) -> Sprite {
        let palettes: [(Color, Color)] = [
            (navy, Color(r: 0, g: 160, b: 255)),
            (Color(r: 128, g: 0, b: 0), Color(r: 255, g: 96, b: 96)),
            (Color(r: 0, g: 96, b: 0), yellow),
            (Color(r: 96, g: 0, b: 128), Color(r: 255, g: 0, b: 255)),
        ]
        let (base, line) = palettes[variant % palettes.count]
        let step = 6 + variant % 3 * 2
        var s = blank()
        for y in 3...(cardH - 4) {
            for x in 3...(cardW - 4) {
                let on = (x + y) % step == 0 || (x - y + 192) % step == 0
                s.set(x, y, on ? line : base)
            }
        }
        return s
    }
}
