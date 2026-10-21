import AppKit
import ScreenSaver

struct Options {
    static let moduleName = "se.jbe.solitairewin"

    var rampMinutes = 8.0
    var maxChaos = 1.0
    var families = Set(Family.allCases)
    var startBroken = false

    private static var defaults: ScreenSaverDefaults? { ScreenSaverDefaults(forModuleWithName: moduleName) }

    static func load() -> Options {
        var o = Options()
        guard let d = defaults else { return o }
        if d.object(forKey: "rampMinutes") != nil { o.rampMinutes = d.double(forKey: "rampMinutes") }
        if d.object(forKey: "maxChaos") != nil { o.maxChaos = d.double(forKey: "maxChaos") }
        if let raw = d.array(forKey: "families") as? [Int] { o.families = Set(raw.compactMap(Family.init(rawValue:))) }
        o.startBroken = d.bool(forKey: "startBroken")
        return o
    }

    func save() {
        guard let d = Self.defaults else { return }
        d.set(rampMinutes, forKey: "rampMinutes")
        d.set(maxChaos, forKey: "maxChaos")
        d.set(families.map(\.rawValue), forKey: "families")
        d.set(startBroken, forKey: "startBroken")
        d.synchronize()
    }
}

/// The "Options…" sheet in System Settings.
final class OptionsSheet: NSObject {
    let window: NSWindow
    private var options = Options.load()
    private let ramp = NSSlider(value: 8, minValue: 2, maxValue: 30, target: nil, action: nil)
    private let rampLabel = NSTextField(labelWithString: "")
    private let maxChaos = NSSlider(value: 1, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let maxLabel = NSTextField(labelWithString: "")
    private var familyBoxes: [Family: NSButton] = [:]
    private let broken = NSButton(checkboxWithTitle: "Start already broken", target: nil, action: nil)

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 360), styleMask: [.titled], backing: .buffered, defer: true)
        super.init()

        ramp.doubleValue = options.rampMinutes
        maxChaos.doubleValue = options.maxChaos
        broken.state = options.startBroken ? .on : .off
        for s in [ramp, maxChaos] {
            s.target = self
            s.action = #selector(changed)
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.addArrangedSubview(rampLabel)
        stack.addArrangedSubview(ramp)
        stack.addArrangedSubview(maxLabel)
        stack.addArrangedSubview(maxChaos)
        stack.addArrangedSubview(NSTextField(labelWithString: "Kinds of trouble:"))
        for f in Family.allCases {
            let b = NSButton(checkboxWithTitle: f.name, target: nil, action: nil)
            b.state = options.families.contains(f) ? .on : .off
            familyBoxes[f] = b
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(broken)
        let ok = NSButton(title: "OK", target: self, action: #selector(done))
        ok.keyEquivalent = "\r"
        stack.addArrangedSubview(ok)
        for s in [ramp, maxChaos] { s.widthAnchor.constraint(equalToConstant: 360).isActive = true }

        window.contentView = stack
        changed()
    }

    @objc private func changed() {
        rampLabel.stringValue = "Minutes until it is fully broken: \(Int(ramp.doubleValue.rounded()))"
        maxLabel.stringValue = String(format: "How broken it gets: %.0f%%", maxChaos.doubleValue * 100)
    }

    @objc private func done() {
        options.rampMinutes = ramp.doubleValue.rounded()
        options.maxChaos = maxChaos.doubleValue
        options.families = Set(familyBoxes.filter { $0.value.state == .on }.map(\.key))
        options.startBroken = broken.state == .on
        options.save()
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.close() }
    }
}
