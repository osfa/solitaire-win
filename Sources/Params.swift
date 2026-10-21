import simd

/// Speeds and accelerations are in virtual pixels per tick; a tick is 1/60 s at time scale 1.
struct PhysicsParams {
    var timeScale = 1.0
    var gravity = SIMD2<Double>(0, 0.5)
    var restitution = 0.75
    var drag = 0.0
    var walls = false
    var ceiling = false
    var orbitStrength = 0.0
    var orbitCenter = SIMD2<Double>(0, 0)
    var homingStrength = 0.0
    var homingTarget = SIMD2<Double>(0, 0)
    var sineAmp = 0.0
    var sineFreq = 0.0
    var jitter = 0.0
    var splitOnBounce = 0
    var teleportRate = 0.0
    var cardScale = 1.0
    var stickyFloor = 0.0
    var wrongLaunch = 0.0
    var parallel = 1
    var showBack = 0.0
}

/// Lengths are in virtual pixels.
struct LookParams {
    var hue = 0.0
    var paletteMix = 0.0
    var paletteShift = 0.0
    var invert = 0.0
    var rgbSplit = 0.0
    var tear = 0.0
    var feltMix = 0.0
    var feltTint = SIMD3<Double>(0, 0.5, 0)
    var atlasOffset = SIMD2<Double>(0, 0)
    var strideExtra = 0.0
    var scroll = SIMD2<Double>(0, 0)
}

struct Params {
    var physics = PhysicsParams()
    var look = LookParams()
}

/// Changes to the trails already on the felt. Lengths are in virtual pixels.
enum CanvasOp {
    case slices(seed: Double, bands: Double, shift: Double)
    case erase(x0: Double, y0: Double, x1: Double, y1: Double)
    case melt(seed: Double, column: Double, amount: Double)
}
