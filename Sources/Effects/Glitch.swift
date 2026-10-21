import Foundation

extension EffectSpec {
    static let glitchEffects: [EffectSpec] = [
        EffectSpec(name: "wrong card", family: .glitch, minChaos: 0.25, weight: 2, duration: 1...6, hard: true) { s in
            let off = SIMD2(s.rng.range(10...60) * s.rng.sign(), s.rng.chance(0.5) ? 0 : s.rng.range(10...80) * s.rng.sign())
            return { p, _ in p.look.atlasOffset += off.rounded(.down) }
        },
        EffectSpec(name: "bad stride", family: .glitch, minChaos: 0.4, weight: 2, duration: 0.5...4, hard: true) { s in
            let extra = (s.rng.range(1...lerp(3, 40, s.intensity)) * s.rng.sign()).rounded()
            return { p, _ in p.look.strideExtra += extra }
        },
        EffectSpec(name: "slices", family: .glitch, minChaos: 0.35, weight: 2, duration: 0.3...2, hard: true) { s in
            let bands = Double(6 + s.rng.int(34))
            let shift = lerp(20, 300, s.intensity)
            var next = 0.0
            return { _, k in
                guard k.t >= next else { return }
                k.engine.canvasOps.append(.slices(seed: k.rng.range(0...1000), bands: bands, shift: shift))
                next = k.t + k.rng.range(0.08...0.4)
            }
        },
        EffectSpec(name: "erase band", family: .glitch, minChaos: 0.3, weight: 1.5, duration: 0.1...0.2, hard: true) { s in
            { _, k in
                guard k.first else { return }
                let size = k.engine.size
                if k.rng.chance(0.6) {
                    let y = k.rng.range(0...size.y), h = k.rng.range(10...size.y * 0.4 * s.intensity + 10)
                    k.engine.canvasOps.append(.erase(x0: 0, y0: y, x1: size.x, y1: y + h))
                } else {
                    let x = k.rng.range(0...size.x), w = k.rng.range(10...size.x * 0.3 * s.intensity + 10)
                    k.engine.canvasOps.append(.erase(x0: x, y0: 0, x1: x + w, y1: size.y))
                }
            }
        },
        EffectSpec(name: "scroll", family: .glitch, minChaos: 0.3, weight: 1.5, duration: 2...8) { s in
            let speed = lerp(20, 400, s.intensity)
            let dir = s.rng.chance(0.5) ? SIMD2<Double>(s.rng.sign(), 0) : SIMD2<Double>(0, s.rng.sign())
            return { p, k in p.look.scroll += dir * speed * k.env }
        },
        EffectSpec(name: "melt", family: .glitch, minChaos: 0.5, weight: 1, duration: 1...5) { s in
            let seed = s.rng.range(0...1000)
            let column = s.rng.range(1...6).rounded()
            let amount = lerp(1, 4, s.intensity)
            return { _, k in k.engine.canvasOps.append(.melt(seed: seed, column: column, amount: amount * k.env)) }
        },
        EffectSpec(name: "card burst", family: .glitch, minChaos: 0.3, weight: 1.5, duration: 0.1...0.2, hard: true) { s in
            let n = Int(lerp(5, 40, s.intensity))
            return { _, k in if k.first { k.engine.spawnBurst(n) } }
        },
        EffectSpec(name: "wrong launch", family: .glitch, minChaos: 0.25, weight: 1.5, duration: 8...20, hard: true) { s in
            let p0 = lerp(0.3, 1, s.intensity)
            return { p, _ in p.physics.wrongLaunch = p0 }
        },
        EffectSpec(name: "flip to back", family: .glitch, minChaos: 0.2, weight: 1.5, duration: 3...10) { s in
            { p, k in p.physics.showBack = s.intensity * k.env }
        },
        EffectSpec(name: "tear", family: .glitch, minChaos: 0.2, weight: 2, duration: 0.5...4, hard: true) { s in
            { p, _ in p.look.tear = max(p.look.tear, s.intensity) }
        },
        EffectSpec(name: "card cycle", family: .glitch, minChaos: 0.25, weight: 1.2, duration: 3...10, hard: true) { s in
            let rate = lerp(0.1, 1, s.intensity)
            return { p, _ in p.physics.cardCycle = rate }
        },

        // Rare.
        EffectSpec(name: "upside down", family: .glitch, minChaos: 0.5, weight: 0.06, duration: 3...8, hard: true) { _ in
            { p, _ in p.look.flipY.toggle() }
        },
        EffectSpec(name: "mirror", family: .glitch, minChaos: 0.4, weight: 0.06, duration: 3...8, hard: true) { _ in
            { p, _ in p.look.flipX.toggle() }
        },
    ]
}
