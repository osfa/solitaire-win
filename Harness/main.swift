import AppKit

/// Runs the saver in a window. Keys: space pause, 1–5 force a family (time, colour, path, physics, glitch),
/// 0 clear effects, +/- chaos, a back to automatic chaos, f clock ×10, r reboot, s print seed, p snapshot.
///
/// Arguments: --seed N, --chaos X, --force FAMILY[,FAMILY], --size WxH, --fps YES, --ff YES (clock ×10), --drawn YES (drawn deck), --effect NAME[,NAME] (e.g. "flip to back"), --effectat SECONDS, --list YES (effect table as JSON),
/// --snap DIR --snaps N --every SECONDS (writes N PNGs then quits).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var saver: SolitaireSaverView!
    var lastTitle = 0.0

    func applicationDidFinishLaunching(_ note: Notification) {
        let args = UserDefaults.standard
        if args.bool(forKey: "list") {
            let rows: [[String: Any]] = EffectSpec.all.map {
                ["name": $0.name, "family": "\($0.family)", "minChaos": $0.minChaos, "weight": $0.weight,
                 "durationMin": $0.duration.lowerBound, "durationMax": $0.duration.upperBound, "hard": $0.hard]
            }
            let data = try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        }
        var size = NSSize(width: 1280, height: 720)
        if let s = args.string(forKey: "size")?.split(separator: "x"), s.count == 2,
           let w = Double(s[0]), let h = Double(s[1]) { size = NSSize(width: w, height: h) }
        let frame = NSRect(origin: .zero, size: size)
        let seed = args.string(forKey: "seed").flatMap(UInt64.init) ?? .random(in: .min ... .max)

        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        var options = Options()
        options.drawnDeck = args.bool(forKey: "drawn")
        saver = SolitaireSaverView(frame: frame, isPreview: false, seed: seed, options: options)
        window.contentView = saver
        window.center()
        window.makeKeyAndOrderFront(nil)
        print("seed \(seed)")

        if args.object(forKey: "chaos") != nil { saver.setChaos(args.double(forKey: "chaos")) }
        let logFPS = args.bool(forKey: "fps")
        var frames = 0
        var since = CACurrentMediaTime()
        saver.onStatus = { [weak self] s in
            guard let self else { return }
            let now = CACurrentMediaTime()
            frames += 1
            if logFPS, now - since >= 2 {
                print(String(format: "%.1f fps · %@", Double(frames) / (now - since), s))
                frames = 0
                since = now
            }
            if now - self.lastTitle > 0.25 {
                self.lastTitle = now
                self.window.title = s
            }
        }
        saver.startAnimation()
        if args.bool(forKey: "ff") { _ = saver.debugKey("f") }

        if let names = args.string(forKey: "force") {
            let byName = Dictionary(uniqueKeysWithValues: Family.allCases.map { ("\($0)", $0) })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for n in names.split(separator: ",") { if let f = byName[String(n)] { self.saver.force(f) } }
            }
        }
        if let names = args.string(forKey: "effect") {
            let at = args.object(forKey: "effectat") != nil ? args.double(forKey: "effectat") : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                for n in names.split(separator: ",") { self.saver.force(named: String(n)) }
            }
        }
        if let dir = args.string(forKey: "snap") {
            let count = max(1, args.integer(forKey: "snaps"))
            let every = args.object(forKey: "every") != nil ? args.double(forKey: "every") : 2
            scheduleSnaps(dir: URL(fileURLWithPath: dir), index: 0, count: count, every: every)
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let key = e.charactersIgnoringModifiers else { return e }
            if key == "p" {
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("solitaire-\(Int(Date().timeIntervalSince1970)).png")
                self.saver.snapshot(to: url)
                print("snapshot \(url.path)")
                return nil
            }
            return self.saver.debugKey(key) ? nil : e
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func scheduleSnaps(dir: URL, index: Int, count: Int, every: Double) {
        guard index < count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + every) {
            let url = dir.appendingPathComponent(String(format: "snap-%02d.png", index))
            self.saver.snapshot(to: url)
            print("snapshot \(url.path)")
            self.scheduleSnaps(dir: dir, index: index + 1, count: count, every: every)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
