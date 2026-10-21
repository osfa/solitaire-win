import Foundation

extension EffectSpec {
    static let colourEffects: [EffectSpec] = [
        EffectSpec(name: "hue cycle", family: .colour, minChaos: 0.05, weight: 3, duration: 6...20) { s in
            let speed = lerp(0.3, 4, s.intensity) * s.rng.sign()
            return { p, k in p.look.hue += k.env * k.t * speed }
        },
        EffectSpec(name: "palette cycle", family: .colour, minChaos: 0.25, weight: 2, duration: 4...15) { s in
            let rate = lerp(2, 20, s.intensity)
            return { p, k in
                p.look.paletteMix = max(p.look.paletteMix, k.env)
                p.look.paletteShift = (k.t * rate).rounded(.down)
            }
        },
        EffectSpec(name: "felt drift", family: .colour, minChaos: 0.05, weight: 2, duration: 8...25) { s in
            let phase = s.rng.unit()
            let amount = lerp(0.4, 1, s.intensity)
            return { p, k in
                p.look.feltMix = max(p.look.feltMix, k.env * amount)
                p.look.feltTint = hsv(phase + k.t * 0.05, 0.9, 0.55)
            }
        },
        EffectSpec(name: "invert flash", family: .colour, minChaos: 0.3, weight: 1.5, duration: 0.5...3, hard: true) { s in
            let rate = lerp(2, 12, s.intensity)
            return { p, k in
                if (k.t * rate).truncatingRemainder(dividingBy: 1) < 0.5 { p.look.invert = 1 - p.look.invert }
            }
        },
        EffectSpec(name: "rgb split", family: .colour, minChaos: 0.15, weight: 2, duration: 1...6) { s in
            let amount = lerp(1, 12, s.intensity)
            return { p, k in p.look.rgbSplit += k.env * amount * (0.6 + 0.4 * sin(k.t * 7)) }
        },
    ]
}

func hsv(_ h: Double, _ s: Double, _ v: Double) -> SIMD3<Double> {
    let hh = (h - h.rounded(.down)) * 6
    let i = Int(hh) % 6
    let f = hh - Double(Int(hh))
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    switch i {
    case 0: return SIMD3(v, t, p)
    case 1: return SIMD3(q, v, p)
    case 2: return SIMD3(p, v, t)
    case 3: return SIMD3(p, q, v)
    case 4: return SIMD3(t, p, v)
    default: return SIMD3(v, p, q)
    }
}
