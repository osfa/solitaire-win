import Foundation
import simd

/// Matches `Stamp` in the shader.
struct Stamp {
    var x: Float
    var y: Float
    var scale: Float
    var card: Int32
    var r: Float = 1
    var g: Float = 1
    var b: Float = 1
}

struct Flyer {
    var card: Int
    var pos: SIMD2<Double>
    var vel: SIMD2<Double>
    var age = 0.0
    var stall = 0.0
    /// Atlas cell of the back it shows instead of its face.
    var back: Int?
    /// Extra cards from glitches; they don't come from a foundation.
    var ghost = false
}

/// The win-screen simulation. Coordinates are virtual pixels, y down, card origin top-left.
final class Engine {
    static let cardSize = SIMD2<Double>(Double(CardArt.cardW), Double(CardArt.cardH))
    static let maxFlyers = 64
    static let maxStamps = 40_000
    /// Flying-card stamps per frame before intermediate steps stop leaving stamps.
    static let stampBudget = 900

    let rng: RNG
    private let backs: [Int]
    private(set) var size = SIMD2<Double>(960, 540)
    private var piles: [[Int]] = []
    private var nextPile = 0
    private var acc = 0.0
    private var roundPause: Double?

    var flyers: [Flyer] = []
    var stamps: [Stamp] = []
    var canvasOps: [CanvasOp] = []
    var wipe = false

    init(rng: RNG, backs: [Int]) {
        self.rng = rng
        self.backs = backs
        restart()
    }

    func resize(_ s: SIMD2<Double>) {
        size = s
        restart()
    }

    func restart() {
        piles = (0..<4).map { suit in (0..<13).map { suit * 13 + $0 } }
        flyers = []
        nextPile = 0
        roundPause = nil
        wipe = true
        stamps = []
        for i in 0..<4 { stamp(card: piles[i].last!, at: pilePos(i), scale: 1) }
    }

    func clearOutput() {
        stamps.removeAll(keepingCapacity: true)
        canvasOps.removeAll(keepingCapacity: true)
        wipe = false
    }

    func pilePos(_ i: Int) -> SIMD2<Double> {
        let gap = (size.x - 12 - Self.cardSize.x) / 6
        return SIMD2(6 + Double(i + 3) * gap, 6)
    }

    func randomSpot() -> SIMD2<Double> {
        SIMD2(rng.range(0...max(1, size.x - Self.cardSize.x)), rng.range(0...max(1, size.y - Self.cardSize.y)))
    }

    func spawnBurst(_ n: Int) {
        for _ in 0..<n where flyers.count < Self.maxFlyers {
            let start = rng.chance(0.5) ? pilePos(rng.int(4)) : SIMD2(rng.range(0...size.x), rng.range(-50...size.y * 0.3))
            flyers.append(Flyer(card: rng.int(52), pos: start,
                                vel: SIMD2(rng.range(1...9) * rng.sign(), -rng.range(0...12)), ghost: true))
        }
    }

    // MARK: Simulation

    func frame(dt: Double, params p: PhysicsParams) {
        if let pause = roundPause {
            roundPause = pause - dt
            if roundPause! <= 0 { restart() }
            return
        }
        let ticks = 60 * dt * p.timeScale
        if ticks == 0 { return }
        if abs(ticks) < 1 {
            step(ticks, p)
        } else {
            acc += abs(ticks)
            let n = min(Int(acc), 600)
            acc -= acc.rounded(.down)
            let every = max(1, (max(flyers.count, 1) * n + Self.stampBudget - 1) / Self.stampBudget)
            for i in 0..<n { step(ticks > 0 ? 1 : -1, p, stamping: (n - 1 - i) % every == 0) }
        }
        if flyers.isEmpty, piles.allSatisfy(\.isEmpty) { roundPause = 2.5 }
    }

    private func launchNext(_ p: PhysicsParams) -> Flyer? {
        for _ in 0..<4 {
            let i = nextPile
            nextPile = (nextPile + 1) % 4
            guard let card = piles[i].popLast() else { continue }
            let pos = rng.chance(p.wrongLaunch) ? randomSpot() : pilePos(i)
            return Flyer(card: card, pos: pos, vel: SIMD2(rng.range(2...7) * rng.sign(), -rng.range(0...8)))
        }
        return nil
    }

    private func step(_ h: Double, _ p: PhysicsParams, stamping: Bool = true) {
        if h > 0 {
            while flyers.lazy.filter({ !$0.ghost }).count < p.parallel, let f = launchNext(p) { flyers.append(f) }
        }
        let cs = Self.cardSize * p.cardScale
        var spawned: [Flyer] = []
        var keep: [Flyer] = []
        keep.reserveCapacity(flyers.count)

        for var f in flyers {
            var a = p.gravity
            let centre = f.pos + cs / 2
            if p.orbitStrength > 0 {
                let d = p.orbitCenter - centre
                a += d / max(simd_length(d), 20) * p.orbitStrength
            }
            if p.homingStrength > 0 {
                let d = p.homingTarget - centre
                let want = d / max(simd_length(d), 1) * 8
                a += (want - f.vel) * 0.05 * p.homingStrength
            }
            if p.jitter > 0 { a += SIMD2(rng.range(-1...1), rng.range(-1...1)) * p.jitter }

            if h > 0 {
                f.vel += a * h
                f.vel *= 1 - p.drag * h
                f.pos += f.vel * h
            } else {
                f.pos += f.vel * h
                f.vel += a * h
            }
            if p.sineAmp != 0 { f.pos.y += p.sineAmp * (sin(p.sineFreq * (f.age + h)) - sin(p.sineFreq * f.age)) }
            f.age += h

            let speed = simd_length(f.vel)
            if speed > 60 { f.vel *= 60 / speed }

            if f.pos.y + cs.y > size.y {
                f.pos.y = size.y - cs.y
                if f.vel.y > 0 {
                    let impact = f.vel.y
                    f.vel.y = -impact * p.restitution
                    f.vel.x *= 1 - p.stickyFloor
                    if p.splitOnBounce > 0, impact > 2 {
                        for _ in 0..<p.splitOnBounce where flyers.count + spawned.count < Self.maxFlyers {
                            var c = f
                            c.ghost = true
                            c.vel = SIMD2(rng.range(-8...8), f.vel.y * rng.range(0.5...1.2))
                            spawned.append(c)
                        }
                    }
                }
            }
            if p.walls {
                if f.pos.x < 0 { f.pos.x = 0; f.vel.x = abs(f.vel.x) }
                if f.pos.x + cs.x > size.x { f.pos.x = size.x - cs.x; f.vel.x = -abs(f.vel.x) }
                if p.ceiling, f.pos.y < 0 { f.pos.y = 0; f.vel.y = abs(f.vel.y) }
            }
            if p.teleportRate > 0, rng.chance(p.teleportRate * abs(h) / 60) { f.pos = randomSpot() }
            if p.showBack > 0 {
                if rng.chance(p.showBack * 0.03 * abs(h)) { f.back = f.back == nil ? backs[rng.int(backs.count)] : nil }
            } else {
                f.back = nil
            }

            if simd_length(f.vel) < 0.3 {
                f.stall += abs(h)
                if f.stall > 240 {
                    f.vel = SIMD2(rng.range(2...6) * rng.sign(), -rng.range(4...12))
                    f.stall = 0
                }
            } else {
                f.stall = 0
            }

            if stamping {
                var card = f.back ?? f.card
                if p.cardCycle > 0 {
                    let cells = 52 + backs.count
                    let i = ((f.card + Int(f.age * p.cardCycle)) % cells + cells) % cells
                    card = i < 52 ? i : backs[i - 52]
                }
                var tint = SIMD3<Double>(1, 1, 1)
                if p.rainbow > 0 {
                    tint = simd_mix(tint, hsv(f.age * p.rainbowSpeed + Double(f.card) / 13, 1, 1), SIMD3(repeating: p.rainbow))
                }
                stamp(card: card, at: f.pos, scale: p.cardScale, tint: tint)
            }

            let gone = f.pos.x + cs.x < -1 || f.pos.x > size.x + 1 || f.pos.y > size.y + 2000 || f.pos.y < -3000
            if !gone || p.walls { keep.append(f) }
        }
        flyers = keep + spawned
    }

    private func stamp(card: Int, at pos: SIMD2<Double>, scale: Double, tint: SIMD3<Double> = SIMD3(1, 1, 1)) {
        guard stamps.count < Self.maxStamps else { return }
        stamps.append(Stamp(x: Float(pos.x.rounded(.down)), y: Float(pos.y.rounded(.down)), scale: Float(scale),
                            card: Int32(card), r: Float(tint.x), g: Float(tint.y), b: Float(tint.z)))
    }
}
