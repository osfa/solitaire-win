import Foundation

extension EffectSpec {
    static let physicsEffects: [EffectSpec] = [
        EffectSpec(name: "super bounce", family: .physics, minChaos: 0.15, weight: 2, duration: 5...15) { s in
            let target = lerp(1.02, 1.25, s.intensity)
            return { p, k in p.physics.restitution = lerp(p.physics.restitution, target, k.env) }
        },
        EffectSpec(name: "dead bounce", family: .physics, minChaos: 0.1, weight: 1.5, duration: 4...10) { s in
            let sticky = lerp(0, 0.3, s.intensity)
            return { p, k in
                p.physics.restitution = lerp(p.physics.restitution, 0.05, k.env)
                p.physics.stickyFloor = sticky * k.env
            }
        },
        EffectSpec(name: "zero g", family: .physics, minChaos: 0.2, weight: 1.5, duration: 3...10) { _ in
            { p, k in p.physics.gravity *= 1 - k.env }
        },
        EffectSpec(name: "split", family: .physics, minChaos: 0.35, weight: 1.5, duration: 4...10, hard: true) { s in
            let n = 1 + Int(s.intensity * 3)
            return { p, _ in p.physics.splitOnBounce = n }
        },
        EffectSpec(name: "teleport", family: .physics, minChaos: 0.4, weight: 1, duration: 2...8, hard: true) { s in
            let rate = lerp(0.5, 6, s.intensity)
            return { p, _ in p.physics.teleportRate = rate }
        },
        EffectSpec(name: "resize", family: .physics, minChaos: 0.2, weight: 1.5, duration: 4...12) { s in
            let target = s.rng.chance(0.5) ? lerp(0.7, 0.25, s.intensity) : lerp(1.5, 4, s.intensity)
            return { p, k in p.physics.cardScale *= lerp(1, target, k.env) }
        },
        EffectSpec(name: "crowd", family: .physics, minChaos: 0.3, weight: 1.5, duration: 6...20, hard: true) { s in
            let n = 2 + Int(s.intensity * 6)
            return { p, _ in p.physics.parallel = n }
        },
    ]
}
