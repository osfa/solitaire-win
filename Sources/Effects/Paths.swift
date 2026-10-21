import Foundation

extension EffectSpec {
    static let pathEffects: [EffectSpec] = [
        EffectSpec(name: "sideways gravity", family: .path, minChaos: 0.1, weight: 2, duration: 4...12) { s in
            let angle = s.rng.range(0.5...3.14) * s.intensity * s.rng.sign()
            return { p, k in
                let a = angle * k.env
                let g = p.physics.gravity
                p.physics.gravity = SIMD2(g.x * cos(a) - g.y * sin(a), g.x * sin(a) + g.y * cos(a))
            }
        },
        EffectSpec(name: "gravity flip", family: .path, minChaos: 0.35, weight: 1.5, duration: 2...6) { _ in
            { p, k in p.physics.gravity.y *= lerp(1, -1, k.env) }
        },
        EffectSpec(name: "orbit", family: .path, minChaos: 0.3, weight: 1.5, duration: 5...15) { s in
            let size = s.engine.size
            let centre = SIMD2(s.rng.range(0.25...0.75) * size.x, s.rng.range(0.25...0.75) * size.y)
            let strength = lerp(0.3, 1.2, s.intensity)
            return { p, k in
                p.physics.orbitCenter = centre
                p.physics.orbitStrength = strength * k.env
                p.physics.gravity *= 1 - k.env
            }
        },
        EffectSpec(name: "sine wave", family: .path, minChaos: 0.1, weight: 2, duration: 4...12) { s in
            let amp = lerp(5, 60, s.intensity)
            let freq = s.rng.range(0.05...0.3)
            return { p, k in
                p.physics.sineAmp = amp * k.env
                p.physics.sineFreq = freq
            }
        },
        EffectSpec(name: "homing", family: .path, minChaos: 0.25, weight: 1.5, duration: 4...10) { s in
            let size = s.engine.size
            let (fx, fy) = (s.rng.range(0.2...0.9), s.rng.range(0.2...0.9))
            let strength = lerp(0.2, 1, s.intensity)
            return { p, k in
                p.physics.homingTarget = SIMD2(size.x * (0.5 + 0.4 * sin(k.t * fx)), size.y * (0.5 + 0.4 * sin(k.t * fy)))
                p.physics.homingStrength = strength * k.env
            }
        },
        EffectSpec(name: "walls", family: .path, minChaos: 0.2, weight: 2, duration: 8...20, hard: true) { s in
            let ceiling = s.intensity > 0.5
            return { p, _ in
                p.physics.walls = true
                p.physics.ceiling = ceiling
            }
        },
        EffectSpec(name: "drunk", family: .path, minChaos: 0.15, weight: 1.5, duration: 3...10) { s in
            let amount = lerp(0.3, 3, s.intensity)
            return { p, k in p.physics.jitter += amount * k.env }
        },
    ]
}
