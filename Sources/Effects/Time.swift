import Foundation

extension EffectSpec {
    static let timeEffects: [EffectSpec] = [
        EffectSpec(name: "slow motion", family: .time, minChaos: 0, weight: 3, duration: 3...10) { s in
            let factor = lerp(0.3, 0.03, s.intensity)
            return { p, k in p.physics.timeScale *= lerp(1, factor, k.env) }
        },
        EffectSpec(name: "burst", family: .time, minChaos: 0.1, weight: 3, duration: 0.3...2.5, hard: true) { s in
            let factor = lerp(4, 30, s.intensity)
            return { p, _ in p.physics.timeScale *= factor }
        },
        EffectSpec(name: "stutter", family: .time, minChaos: 0.2, weight: 2, duration: 2...6, hard: true) { s in
            let period = s.rng.range(0.15...0.5)
            return { p, k in
                p.physics.timeScale *= (k.t / period).truncatingRemainder(dividingBy: 1) < 0.7 ? 0 : 3.3
            }
        },
        EffectSpec(name: "rewind", family: .time, minChaos: 0.4, weight: 1.5, duration: 0.7...3, hard: true) { s in
            let factor = -lerp(1, 4, s.intensity)
            return { p, _ in p.physics.timeScale *= factor }
        },
        EffectSpec(name: "lurch", family: .time, minChaos: 0.3, weight: 1.5, duration: 4...12) { s in
            let depth = lerp(0.7, 2.5, s.intensity)
            let rate = s.rng.range(1.5...5)
            return { p, k in p.physics.timeScale *= exp(sin(k.t * rate) * depth * k.env) }
        },
        EffectSpec(name: "hang", family: .time, minChaos: 0.3, weight: 1, duration: 1...4, hard: true) { _ in
            { p, _ in p.physics.timeScale = 0 }
        },
    ]
}
