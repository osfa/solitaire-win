import MetalKit
import ScreenSaver

@objc(SolitaireSaverView)
final class SolitaireSaverView: ScreenSaverView {
    private static let instances = NSHashTable<SolitaireSaverView>.weakObjects()

    private let mtkView: MTKView
    private var renderer: Renderer?
    private let engine: Engine
    private let director: Director
    private var lastTime: CFTimeInterval?
    private var halted = false
    private var paused = false
    private var optionsSheet: OptionsSheet?

    var onStatus: ((String) -> Void)?
    var seed: UInt64 { engine.rng.seed }

    convenience override init?(frame: NSRect, isPreview: Bool) {
        self.init(frame: frame, isPreview: isPreview, seed: .random(in: .min ... .max), options: Options.load())
    }

    init?(frame: NSRect, isPreview: Bool, seed: UInt64, options: Options) {
        let rng = RNG(seed: seed)
        engine = Engine(rng: rng)
        director = Director(rng: rng, options: options, isPreview: isPreview)
        mtkView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60
        mtkView.autoresizingMask = [.width, .height]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        addSubview(mtkView)
        renderer = Renderer(view: mtkView)
        if !isPreview {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(willStop), name: .init("com.apple.screensaver.willstop"), object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    override func startAnimation() {
        super.startAnimation()
        halted = false
        lastTime = nil
        // legacyScreenSaver keeps old views alive; only the newest one per screen draws.
        let screen = window?.screen
        for other in Self.instances.allObjects where other !== self && other.isPreview == isPreview {
            if screen == nil || other.window?.screen == screen { other.halted = true }
        }
        Self.instances.add(self)
    }

    override func stopAnimation() {
        super.stopAnimation()
        halted = true
    }

    @objc private func willStop(_ note: Notification) { halted = true }

    override func draw(_ rect: NSRect) {}

    override func animateOneFrame() {
        guard !halted, let renderer else { return }
        let now = CACurrentMediaTime()
        let dt = min(lastTime.map { now - $0 } ?? 1.0 / 60, 0.1)
        lastTime = now
        if renderer.ensureTargets(size: mtkView.drawableSize) { engine.resize(renderer.virtualSize) }
        guard renderer.hasTargets else { return }

        var params = Params()
        if !paused {
            params = director.update(dt: dt, engine: engine)
            engine.frame(dt: dt, params: params.physics)
        }
        renderer.render(in: mtkView, engine: engine, params: params, dt: paused ? 0 : dt)
        engine.clearOutput()
        onStatus?(director.status)
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let sheet = OptionsSheet()
        optionsSheet = sheet
        return sheet.window
    }

    // MARK: Harness controls

    /// Returns true when the key was handled.
    func debugKey(_ key: String) -> Bool {
        switch key {
        case " ": paused.toggle()
        case "1", "2", "3", "4", "5": director.force(Family(rawValue: Int(key)! - 1)!, engine: engine)
        case "0": director.clearEffects()
        case "=", "+": director.chaosOverride = min(1, (director.chaosOverride ?? director.chaos) + 0.1)
        case "-": director.chaosOverride = max(0, (director.chaosOverride ?? director.chaos) - 0.1)
        case "a": director.chaosOverride = nil
        case "f": director.clockSpeed = director.clockSpeed > 1 ? 1 : 10
        case "r": director.reboot()
        case "s": print("seed \(seed)")
        default: return false
        }
        return true
    }

    func setChaos(_ c: Double?) { director.chaosOverride = c }

    func force(_ family: Family) { director.force(family, engine: engine) }

    func snapshot(to url: URL) { renderer?.requestSnapshot(to: url) }
}
