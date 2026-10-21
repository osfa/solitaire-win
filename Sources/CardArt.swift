import AppKit

/// RGBA8, row-major. Cells are 71×96, 13 per row; rows: spades, hearts, clubs, diamonds, then backs.
struct Atlas {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    /// Cell indices that hold card backs.
    let backs: [Int]
}

/// Pixel-art deck at the original 71×96 card size, laid out like the Windows deck.
enum CardArt {
    static let cardW = 71
    static let cardH = 96
    static let columns = 13
    static let rows = 5
    static let atlasW = cardW * columns
    static let atlasH = cardH * rows

    /// The original deck as a sprite sheet (`cards.png`, 923×576) if bundled, otherwise the drawn deck.
    static func atlas(bundle: Bundle, preferDrawn: Bool) -> Atlas {
        if !preferDrawn, let sheet = loadSheet(bundle: bundle) { return sheet }
        return Atlas(bytes: makeAtlas(), width: atlasW, height: atlasH, backs: Array(52..<65))
    }

    /// The sheet's background green shows through at card corners and in empty cells.
    private static func loadSheet(bundle: Bundle) -> Atlas? {
        guard let url = bundle.url(forResource: "cards", withExtension: "png"),
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.width == atlasW, image.height == cardH * 6 else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i] == 0 && bytes[i + 1] == 99 && bytes[i + 2] == 0 {
            bytes[i + 3] = 0
        }
        return Atlas(bytes: bytes, width: w, height: h, backs: Array(52..<62) + Array(65..<74))
    }

    struct Color: Equatable { var r, g, b: UInt8; var a: UInt8 = 255 }
    static let white = Color(r: 255, g: 255, b: 255)
    static let black = Color(r: 0, g: 0, b: 0)
    static let red = Color(r: 255, g: 0, b: 0)
    static let blue = Color(r: 0, g: 0, b: 255)
    static let navy = Color(r: 0, g: 0, b: 128)
    static let yellow = Color(r: 255, g: 255, b: 0)
    static let clear = Color(r: 0, g: 0, b: 0, a: 0)

    typealias Glyph = [[Bool]]

    static func glyph(_ rows: [String]) -> Glyph { rows.map { $0.map { $0 == "#" } } }

    /// Symmetric shape from row widths, centred in `width`.
    static func widths(_ ws: [Int], width: Int) -> Glyph {
        ws.map { w in (0..<width).map { abs(2 * $0 - (width - 1)) < w } }
    }

    struct Sprite {
        let w: Int, h: Int
        var px: [Color]

        init(w: Int, h: Int, fill: Color) {
            self.w = w
            self.h = h
            px = Array(repeating: fill, count: w * h)
        }

        func get(_ x: Int, _ y: Int) -> Color {
            guard x >= 0, y >= 0, x < w, y < h else { return CardArt.clear }
            return px[y * w + x]
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

        mutating func frame(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Color) {
            rect(x0, y0, x1, y0, c)
            rect(x0, y1, x1, y1, c)
            rect(x0, y0, x0, y1, c)
            rect(x1, y0, x1, y1, c)
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

        /// Turns white pixels next to a colour other than black or white into black, for a drawn outline.
        mutating func outline(within x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            var marks: [(Int, Int)] = []
            for y in y0...y1 {
                for x in x0...x1 where get(x, y) == CardArt.white {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let n = get(x + dx, y + dy)
                        if n.a > 0, n != CardArt.white, n != CardArt.black { marks.append((x, y)); break }
                    }
                }
            }
            for (x, y) in marks { set(x, y, CardArt.black) }
        }
    }

    // MARK: Glyphs (spades, hearts, clubs, diamonds)

    static let pips: [Glyph] = [
        glyph([".......#.......", "......###......", ".....#####.....", "....#######....", "...#########...",
               "..###########..", ".#############.", "###############", "###############", "###############",
               "###############", ".#####.#.#####.", "..###..#..###..", "......###......", ".....#####....."]),
        glyph(["..####...####..", ".######.######.", "###############", "###############", "###############",
               "###############", "###############", ".#############.", "..###########..", "...#########...",
               "....#######....", ".....#####.....", "......###......", ".......#......."]),
        glyph([".....#####.....", "....#######....", "....#######....", "....#######....", ".....#####.....",
               "..###.###.###..", ".#############.", "###############", "###############", "###############",
               ".#####.#.#####.", "..###..#..###..", "......###......", ".....#####....."]),
        widths([1, 3, 5, 7, 9, 11, 13, 13, 13, 11, 9, 7, 5, 3, 1], width: 13),
    ]

    static let smallSuits: [Glyph] = [
        glyph(["....#....", "...###...", "..#####..", ".#######.", "#########", "#########", "#########",
               ".##.#.##.", "....#....", "...###..."]),
        glyph([".##...##.", "####.####", "#########", "#########", "#########", ".#######.", "..#####..",
               "...###...", "....#...."]),
        glyph(["...###...", "..#####..", "..#####..", "..#####..", "##.###.##", "#########", "#########",
               "##.#.#.##", "....#....", "...###..."]),
        widths([1, 3, 5, 7, 7, 7, 5, 3, 1], width: 7),
    ]

    static let rankGlyphs: [Glyph] = {
        let one = Array(repeating: "##", count: 12)
        let zero = [".####.", "######"] + Array(repeating: "##..##", count: 8) + ["######", ".####."]
        let ten = zip(one, zero).map { $0 + "." + $1 }
        return [
            glyph(["...##...", "...##...", "..####..", "..####..", ".##..##.", ".##..##.", ".##..##.", ".######.",
                   "########", "##....##", "##....##", "##....##"]),
            glyph([".#####.", "#######", "##...##", ".....##", "....##.", "...##..", "..##...", ".##....",
                   "##.....", "##.....", "#######", "#######"]),
            glyph(["#######", "#######", "....##.", "...##..", "..####.", "..#####", ".....##", ".....##",
                   "##...##", "##...##", "#######", ".#####."]),
            glyph(["....##.", "...###.", "..####.", ".##.##.", "##..##.", "##..##.", "#######", "#######",
                   "....##.", "....##.", "...####", "...####"]),
            glyph(["#######", "#######", "##.....", "##.....", "######.", "#######", ".....##", ".....##",
                   "##...##", "##...##", "#######", ".#####."]),
            glyph(["..####.", ".#####.", "##.....", "##.....", "######.", "#######", "##...##", "##...##",
                   "##...##", "##...##", "#######", ".#####."]),
            glyph(["#######", "#######", "##...##", ".....##", "....##.", "....##.", "...##..", "...##..",
                   "..##...", "..##...", "..##...", "..##..."]),
            glyph([".#####.", "#######", "##...##", "##...##", "#######", ".#####.", "#######", "##...##",
                   "##...##", "##...##", "#######", ".#####."]),
            glyph([".#####.", "#######", "##...##", "##...##", "##...##", "#######", ".######", ".....##",
                   ".....##", ".....##", ".#####.", ".####.."]),
            glyph(ten),
            glyph(["..#####", "..#####", "....##.", "....##.", "....##.", "....##.", "....##.", "....##.",
                   "##..##.", "##..##.", "######.", ".####.."]),
            glyph([".#####..", "#######.", "##...##.", "##...##.", "##...##.", "##...##.", "##...##.", "##.####.",
                   "##..###.", "#######.", ".#######", "......##"]),
            glyph(["##...##.", "##..##..", "##.##...", "####....", "###.....", "####....", "##.##...", "##..##..",
                   "##..##..", "##...##.", "##...##.", "##....##"]),
        ]
    }()

    /// Pip spots for 2…10: (column −1/0/1, fraction from the top row to the bottom row).
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

    /// The drawn deck: RGBA8, row-major, atlasW × atlasH.
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

    /// White card with a 1-pixel border and three see-through pixels at each corner.
    static func blank(ink: Color = black) -> Sprite {
        var s = Sprite(w: cardW, h: cardH, fill: white)
        let (r, b) = (cardW - 1, cardH - 1)
        s.rect(2, 0, r - 2, 0, ink)
        s.rect(2, b, r - 2, b, ink)
        s.rect(0, 2, 0, b - 2, ink)
        s.rect(r, 2, r, b - 2, ink)
        for (x, y) in [(1, 1), (r - 1, 1), (1, b - 1), (r - 1, b - 1)] { s.set(x, y, ink) }
        for (x, y) in [(0, 0), (1, 0), (0, 1), (r, 0), (r - 1, 0), (r, 1),
                       (0, b), (1, b), (0, b - 1), (r, b), (r - 1, b), (r, b - 1)] { s.set(x, y, clear) }
        return s
    }

    static func face(suit: Int, rank: Int) -> Sprite {
        let ink = suit == 1 || suit == 3 ? red : black
        var s = blank(ink: ink)
        let rg = rankGlyphs[rank]
        let rw = rg[0].count
        s.glyph(rg, 3, 4, ink)
        s.glyph(rg, cardW - 3 - rw, cardH - 4 - rg.count, ink, rotated: true)
        let sm = smallSuits[suit]
        let sx = 3 + (9 - sm[0].count) / 2
        s.glyph(sm, sx, 19, ink)
        s.glyph(sm, cardW - sx - sm[0].count, cardH - 19 - sm.count, ink, rotated: true)

        let pip = pips[suit]
        let pw = pip[0].count
        switch rank {
        case 0 where suit == 0:
            s.blit(aceOfSpades(), 13, 24)
        case 0:
            s.glyph(pip, 35 - pw / 2, 48 - pip.count / 2, ink)
        case 1...9:
            for (col, f) in pipLayout[rank - 1] {
                let cx = 35 + col * 13
                let top = 10 + Int((f * 61).rounded())
                s.glyph(pip, cx - pw / 2, top + (15 - pip.count) / 2, ink, rotated: f > 0.5)
            }
        default:
            let half = courtHalf(suit: suit, rank: rank, ink: ink)
            s.blit(half, 13, 12)
            s.blit(half, 13, 12 + half.h, rotated: true)
            s.frame(12, 11, 58, 84, black)
        }
        return s
    }

    /// Large spade with an inner outline and a small spade inside, 45×48.
    static func aceOfSpades() -> Sprite {
        let w = 45, h = 48
        func inside(_ x: Int, _ y: Int, inset: Double) -> Bool {
            let u = (Double(x) - 22) / 20, v = Double(y) / 20
            let e = inset / 20
            let lobeL = hypot(u + 0.48, v - 1.25) < 0.52 - e
            let lobeR = hypot(u - 0.48, v - 1.25) < 0.52 - e
            let top = v > e * 1.6 && v < 1.3 && abs(u) < (v - e * 1.6) * 0.82
            let stem = abs(u) < 0.06 + max(0, v - 1.6) * 0.55 - e && v > 1.3 && v < 2.25 - e
            return lobeL || lobeR || top || stem
        }
        var s = Sprite(w: w, h: h, fill: clear)
        for y in 0..<h {
            for x in 0..<w where inside(x, y, inset: 0) {
                let ring = inside(x, y, inset: 3) && !inside(x, y, inset: 4)
                let ring2 = inside(x, y, inset: 7) && !inside(x, y, inset: 8)
                s.set(x, y, ring || ring2 ? white : black)
            }
        }
        return s
    }

    // MARK: Court cards

    /// Top half of a court picture, 45×36, inside the frame. The card shows it twice, the second turned 180°.
    /// The figure is symmetric about column `ax`: a patterned centre panel, striped panels, then solid outer panels.
    static func courtHalf(suit: Int, rank: Int, ink: Color) -> Sprite {
        var s = Sprite(w: 45, h: 36, fill: white)
        let ax = 28
        let swap = (suit + rank) % 2 == 1
        let robe = swap ? yellow : red
        let trim = swap ? red : yellow
        let jewel = suit % 2 == 0 ? blue : red

        func mirror(_ d: Int, _ y: Int, _ c: Color) {
            s.set(ax - d, y, c)
            s.set(ax + d, y, c)
        }

        // Torso.
        for y in 17...35 {
            let reach = y < 22 ? 16 - (22 - y) * 2 : 16
            for d in 0...reach {
                var c: Color
                switch d {
                case 0...3:
                    switch rank {
                    case 12: c = (d + y) % 2 == 0 ? black : white
                    case 11: c = (d + y) % 4 == 0 ? red : yellow
                    default: c = y % 2 == 0 ? black : white
                    }
                case 4, 10: c = black
                case 5...9: c = d % 2 == 0 ? black : trim
                default: c = robe
                }
                mirror(d, y, c)
            }
        }
        // The axis is right of centre, so widen the left side to meet the frame where the halves join.
        for y in 23...35 {
            let x0 = max(0, 11 - (y - 23) * 3)
            for x in x0...(ax - 17) { s.set(x, y, y % 4 == 0 ? black : x % 5 == 2 ? trim : robe) }
        }
        for y in stride(from: 20, through: 33, by: 5) {
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] { mirror(13 + dx, y + dy, trim) }
            mirror(13, y, black)
        }
        for d in 0...16 { mirror(d, 29, black) }
        for d in 0...16 { mirror(d, 30, d % 2 == 0 ? trim : black) }
        if rank == 12 {
            s.rect(ax - 1, 23, ax + 1, 25, robe)
            s.set(ax, 24, jewel)
        }

        // Collar.
        for d in 0...9 {
            mirror(d, 15, d % 2 == 0 ? trim : black)
            mirror(d, 16, black)
        }

        // Head.
        s.rect(ax - 6, 4, ax + 6, 14, white)
        s.rect(ax - 7, 4, ax - 7, 13, black)
        s.rect(ax + 7, 4, ax + 7, 13, black)
        s.rect(ax - 6, 14, ax + 6, 14, black)
        for d in 2...4 { mirror(d, 6, black) }
        mirror(3, 7, black)
        s.rect(ax, 7, ax, 10, black)
        s.set(ax - 1, 10, black)
        s.rect(ax - 2, 12, ax + 2, 12, red)

        switch rank {
        case 12: // King: crown, beard, sword.
            s.rect(ax - 7, 0, ax + 7, 3, yellow)
            for d in stride(from: 1, through: 7, by: 3) { mirror(d, 0, white) }
            for d in stride(from: 0, through: 6, by: 2) { mirror(d, 2, d % 4 == 0 ? jewel : black) }
            for y in 4...10 { mirror(8, y, y % 2 == 0 ? yellow : black) }
            for y in 11...16 { for d in 0...6 { mirror(d, y, d % 2 == 0 ? yellow : black) } }
            s.rect(ax - 2, 11, ax + 2, 11, red)
            s.rect(41, 0, 43, 17, white)
            s.rect(40, 0, 40, 17, black)
            s.rect(44, 0, 44, 17, black)
            s.rect(38, 15, 44, 16, yellow)
        case 11: // Queen: small crown, long hair, sceptre.
            s.rect(ax - 4, 0, ax + 4, 2, yellow)
            mirror(4, 0, white); mirror(2, 0, white)
            s.set(ax, 1, jewel)
            for y in 2...19 { for d in 7...9 { mirror(d, y, (y + d) % 2 == 0 ? yellow : black) } }
            s.rect(17, 3, 17, 18, black)
            s.rect(16, 1, 18, 3, red)
            s.set(17, 2, yellow)
        default: // Jack: cap with feather, halberd.
            s.rect(ax - 7, 0, ax + 7, 2, robe)
            s.rect(ax - 7, 3, ax + 7, 3, trim)
            for i in 0...6 { s.set(ax + 8 + i, 2 - i / 3, yellow) }
            for y in 4...11 { mirror(8, y, y % 2 == 0 ? yellow : black) }
            s.rect(41, 0, 41, 17, black)
            for y in 1...7 { s.rect(41, y, 41 + min(y, 8 - y), y, yellow) }
        }

        s.outline(within: 0, 0, 44, 35)
        let pip = pips[suit]
        s.glyph(pip, 1 + (15 - pip[0].count) / 2, 1, ink)
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
