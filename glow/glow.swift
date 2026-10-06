// glow: a click-through glowing border around every screen while Claude drives the mouse and keyboard.
// The overlay shows while ~/.config/glow/ping is fresh and quits on its own once it goes stale,
// so a crash or a forgotten "off" can never leave the screen lit.
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let dir = "\(home)/.config/glow"
let pingFile = "\(dir)/ping"
let showFor: TimeInterval = 4      // seconds a ping keeps the border lit
let quitAfter: TimeInterval = 90   // seconds without a ping before the daemon exits

func lastPing() -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: pingFile))?[.modificationDate] as? Date
}

final class GlowView: NSView {
    private let ring = CAShapeLayer()
    private let label = CATextLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let accent = NSColor(red: 0.29, green: 0.55, blue: 1.0, alpha: 1).cgColor
        ring.fillColor = nil
        ring.strokeColor = accent
        ring.lineWidth = 6
        ring.shadowColor = accent
        ring.shadowRadius = 18
        ring.shadowOpacity = 1
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)

        label.string = "Claude is using your Mac"
        label.fontSize = 13
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.foregroundColor = NSColor.white.cgColor
        label.backgroundColor = NSColor(red: 0.18, green: 0.36, blue: 0.85, alpha: 0.92).cgColor
        label.cornerRadius = 8
        label.alignmentMode = .center
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(label)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ring.add(pulse, forKey: "pulse")
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset = ring.lineWidth / 2 + 1
        ring.frame = bounds
        ring.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: 12, cornerHeight: 12, transform: nil)
        let w: CGFloat = 210, h: CGFloat = 26
        // bottom centre, clear of the menu bar and of where most dialogs appear
        label.frame = CGRect(x: (bounds.width - w) / 2, y: 18, width: w, height: h)
    }
}

final class App: NSObject, NSApplicationDelegate {
    var panels: [NSPanel] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        buildPanels()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.buildPanels()
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func buildPanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            p.contentView = GlowView(frame: NSRect(origin: .zero, size: screen.frame.size))
            p.setFrame(screen.frame, display: true)
            return p
        }
    }

    func tick() {
        let age = lastPing().map { -$0.timeIntervalSinceNow } ?? .infinity
        if age > quitAfter { NSApp.terminate(nil) }
        let show = age < showFor
        for p in panels {
            // orderFrontRegardless never activates the app, so the driven app keeps keyboard focus
            if show && !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless(); p.animator().alphaValue = 1 }
            if !show && p.isVisible { p.orderOut(nil) }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
