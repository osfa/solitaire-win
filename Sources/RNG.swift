import Foundation

/// SplitMix64.
final class RNG {
    let seed: UInt64
    private var state: UInt64

    init(seed: UInt64) {
        self.seed = seed
        state = seed
    }

    func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    func unit() -> Double { Double(next() >> 11) * 0x1p-53 }

    func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + unit() * (r.upperBound - r.lowerBound) }

    func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }

    func chance(_ p: Double) -> Bool { unit() < p }

    func sign() -> Double { chance(0.5) ? 1 : -1 }

    func pick<T>(_ items: [T], weight: (T) -> Double) -> T? {
        let total = items.reduce(0) { $0 + weight($1) }
        guard total > 0 else { return nil }
        var x = unit() * total
        for item in items {
            x -= weight(item)
            if x <= 0 { return item }
        }
        return items.last
    }
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
