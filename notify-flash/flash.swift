// notify-flash: a click-through glowing border and a big message in the middle of every screen.
// Usage: notify-flash "<message>" "<subtitle>" done|needs
// It stays until Herdr comes to the front (or 25 seconds pass), so a glance away still sees it.
import AppKit

let args = CommandLine.arguments
let message = args.count > 1 ? args[1] : "Claude is done"
let subtitle = args.count > 2 ? args[2] : ""
let isNeeds = args.count > 3 && args[3] == "needs"
let herdrId = "dev.herdr.app"
let maxShow: TimeInterval = 25
let minShow: TimeInterval = 1.5

let accent = isNeeds
    ? NSColor(red: 1.0, green: 0.62, blue: 0.1, alpha: 1)
    : NSColor(red: 0.13, green: 0.85, blue: 0.45, alpha: 1)

final class FlashView: NSView {
    private let ring = CAShapeLayer()
    private let pill = CALayer()
    private let title = CATextLayer()
    private let sub = CATextLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.fillColor = nil
        ring.strokeColor = accent.cgColor
        ring.lineWidth = 14
        ring.shadowColor = accent.cgColor
        ring.shadowRadius = 40
        ring.shadowOpacity = 1
        ring.shadowOffset = .zero
        layer?.addSublayer(ring)

        pill.backgroundColor = accent.cgColor
        pill.cornerRadius = 28
        pill.shadowColor = NSColor.black.cgColor
        pill.shadowOpacity = 0.35
        pill.shadowRadius = 30
        layer?.addSublayer(pill)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for (t, size, text) in [(title, 54.0, message), (sub, 24.0, subtitle)] {
            t.string = text
            t.fontSize = size
            t.font = NSFont.systemFont(ofSize: size, weight: .bold)
            t.foregroundColor = NSColor(white: 0.06, alpha: 1).cgColor
            t.alignmentMode = .center
            t.contentsScale = scale
            pill.addSublayer(t)
        }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.55
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ring.add(pulse, forKey: "pulse")

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.6
        pop.toValue = 1.0
        pop.damping = 8
        pop.duration = pop.settlingDuration
        pill.add(pop, forKey: "pop")
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset = ring.lineWidth / 2 + 1
        ring.frame = bounds
        ring.path = CGPath(rect: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        let w: CGFloat = 620, h: CGFloat = subtitle.isEmpty ? 120 : 160
        pill.frame = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2 + 60, width: w, height: h)
        title.frame = CGRect(x: 0, y: subtitle.isEmpty ? 28 : 62, width: w, height: 66)
        sub.frame = CGRect(x: 0, y: 24, width: w, height: 32)
    }
}

final class App: NSObject, NSApplicationDelegate {
    var panels: [NSPanel] = []
    let started = Date()

    func applicationDidFinishLaunching(_ note: Notification) {
        panels = NSScreen.screens.map { screen in
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            p.contentView = FlashView(frame: NSRect(origin: .zero, size: screen.frame.size))
            p.setFrame(screen.frame, display: true)
            p.orderFrontRegardless()
            return p
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func tick() {
        let age = -started.timeIntervalSinceNow
        let inHerdr = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == herdrId
        if age > maxShow || (inHerdr && age > minShow) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
