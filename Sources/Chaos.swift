import Foundation

enum Family: Int, CaseIterable {
    case time, colour, path, physics, glitch

    var name: String {
        switch self {
        case .time: return "Time (slow, bursts, stutter)"
        case .colour: return "Colour (cycling, palette, invert)"
        case .path: return "Paths (gravity, orbits, waves)"
        case .physics: return "Physics (bounce, split, teleport)"
        case .glitch: return "Glitches (corruption, tearing)"
        }
    }
}

struct EffectSetup {
    let rng: RNG
    let intensity: Double
    let engine: Engine
}

struct EffectTick {
    /// 0…1 fade in/out; always 1 for hard effects.
    let env: Double
    /// Seconds since the effect started.
    let t: Double
    let dt: Double
    let rng: RNG
    let engine: Engine
    let first: Bool
}

typealias EffectBody = (inout Params, EffectTick) -> Void

struct EffectSpec {
    let name: String
    let family: Family
    let minChaos: Double
    let weight: Double
    let duration: ClosedRange<Double>
    var hard = false
    let make: (EffectSetup) -> EffectBody

    static var all: [EffectSpec] { timeEffects + colourEffects + pathEffects + physicsEffects + glitchEffects }
}

final class ActiveEffect {
    let spec: EffectSpec
    let start: Double
    let duration: Double
    let body: EffectBody
    var ticks = 0

    init(spec: EffectSpec, start: Double, duration: Double, body: @escaping EffectBody) {
        self.spec = spec
        self.start = start
        self.duration = duration
        self.body = body
    }
}

/// Decides how broken things are and which effects run.
final class Director {
    let rng: RNG
    let options: Options
    let isPreview: Bool

    private(set) var clock: Double
    var clockSpeed = 1.0
    var chaosOverride: Double?
    private(set) var active: [ActiveEffect] = []
    private var now = 0.0
    private var nextRoll = 1.0
    private var nextReboot = 0.0
    private var rebootLeft: Double?

    init(rng: RNG, options: Options, isPreview: Bool) {
        self.rng = rng
        self.options = options
        self.isPreview = isPreview
        clock = 0
        clock = options.startBroken ? clockFor(chaos: 0.6) : 0
        scheduleReboot()
    }

    private var ramp: Double { options.rampMinutes * 60 }
    private var delay: Double { ramp * 0.25 }

    var chaos: Double {
        if let o = chaosOverride { return o }
        let x = clamp01((clock - delay) / ramp)
        let c = x * x * (3 - 2 * x) * options.maxChaos
        return isPreview ? min(c, 0.5) : c
    }

    private func clockFor(chaos c: Double) -> Double {
        let y = clamp01(c / max(options.maxChaos, 0.01))
        return delay + ramp * (0.5 - sin(asin(1 - 2 * y) / 3))
    }

    private func scheduleReboot() {
        nextReboot = delay + ramp + rng.range(120...600)
    }

    var status: String {
        let names = active.map(\.spec.name).joined(separator: ", ")
        let speed = clockSpeed > 1 ? " ×\(Int(clockSpeed))" : ""
        return String(format: "chaos %.2f%@ · %@", chaos, speed, rebootLeft != nil ? "REBOOT" : names)
    }

    func update(dt: Double, engine: Engine) -> Params {
        now += dt
        clock += dt * clockSpeed
        var p = Params()

        if rebootLeft == nil, clock >= nextReboot, chaosOverride == nil { rebootLeft = 1.2 }
        if let left = rebootLeft {
            p.physics.timeScale = 0
            p.look.tear = 0.5
            rebootLeft = left - dt
            if rebootLeft! <= 0 { finishReboot(engine) }
            return p
        }

        if now >= nextRoll {
            nextRoll = now + 1
            roll(engine)
        }

        for e in active {
            let t = now - e.start
            let fade = e.spec.hard ? 0 : min(1.5, e.duration * 0.2)
            let env = fade == 0 ? 1 : clamp01(min(t / fade, (e.duration - t) / fade))
            e.body(&p, EffectTick(env: env, t: t, dt: dt, rng: rng, engine: engine, first: e.ticks == 0))
            e.ticks += 1
        }
        active.removeAll { now - $0.start > $0.duration }
        return p
    }

    func reboot() { rebootLeft = 1.2 }

    private func finishReboot(_ engine: Engine) {
        rebootLeft = nil
        active.removeAll()
        engine.restart()
        clock = clockFor(chaos: 0.2)
        scheduleReboot()
    }

    private func roll(_ engine: Engine) {
        let c = chaos
        guard c > 0.01, active.count < 1 + Int(3 * c), rng.chance(0.03 + 0.5 * c * c) else { return }
        let running = Set(active.map(\.spec.name))
        let pool = EffectSpec.all.filter {
            options.families.contains($0.family) && $0.minChaos <= c && !running.contains($0.name)
        }
        guard let spec = rng.pick(pool, weight: \.weight) else { return }
        start(spec, intensity: rng.range(0.3...1) * lerp(0.4, 1, c), durationScale: lerp(0.6, 1.5, c), engine: engine)
    }

    func force(_ family: Family, engine: Engine) {
        let pool = EffectSpec.all.filter { $0.family == family }
        guard let spec = rng.pick(pool, weight: { _ in 1 }) else { return }
        start(spec, intensity: rng.range(0.6...1), durationScale: 1, engine: engine)
    }

    func force(named name: String, engine: Engine) {
        guard let spec = EffectSpec.all.first(where: { $0.name == name }) else { return }
        start(spec, intensity: 1, durationScale: 3, engine: engine)
    }

    func clearEffects() { active.removeAll() }

    private func start(_ spec: EffectSpec, intensity: Double, durationScale: Double, engine: Engine) {
        let body = spec.make(EffectSetup(rng: rng, intensity: intensity, engine: engine))
        active.append(ActiveEffect(spec: spec, start: now, duration: rng.range(spec.duration) * durationScale, body: body))
    }
}
