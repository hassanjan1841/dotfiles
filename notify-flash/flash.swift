// notify-flash: full-screen calm cover listing Claude Code sessions that finished or need you, one clickable card each.
// Cards live as JSON files in ~/.config/claude-notify/queue (written by bin/claude-notify).
// Click a card: Herdr opens on that terminal. Click the backdrop: dismiss all. Herdr in front: all clear.
// Colours follow dark-theme guidance: off-white text on dark gray (no pure black or white), desaturated accents.
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let queueDir = "\(home)/.config/claude-notify/queue"
let herdrId = "dev.herdr.app"
let maxAge: TimeInterval = 3 * 3600

// Everything scales with the screen so it looks the same on a laptop and on a 27 inch display.
let k: CGFloat = {
    let w = (NSScreen.main ?? NSScreen.screens[0]).frame.width
    return min(1.8, max(1.15, w / 1500))
}()

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let bgDeep = rgb(15, 17, 21)
let bgGlow = rgb(36, 41, 52)
let surface = rgb(30, 33, 41)
let ink = rgb(232, 234, 238)
let inkDark = rgb(15, 17, 21)
let mint = rgb(134, 214, 178)
let amber = rgb(228, 186, 112)

struct Item {
    let path: String
    let title, project, body, kind, terminal: String
    let time: Double
    var needs: Bool { kind == "needs" }
}

func loadItems() -> [Item] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: queueDir)) ?? []
    var items: [Item] = []
    for n in names where n.hasSuffix(".json") {
        let p = "\(queueDir)/\(n)"
        guard let d = FileManager.default.contents(atPath: p),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
        let t = (j["time"] as? Double) ?? 0
        if Date().timeIntervalSince1970 - t > maxAge { try? FileManager.default.removeItem(atPath: p); continue }
        items.append(Item(path: p, title: j["title"] as? String ?? "Claude", project: j["project"] as? String ?? "",
                          body: j["body"] as? String ?? "", kind: j["kind"] as? String ?? "done",
                          terminal: j["terminal"] as? String ?? "", time: t))
    }
    return items.sorted { $0.time > $1.time }
}

func openHerdr(terminal: String) {
    var cmd = "open -b \(herdrId)"
    if !terminal.isEmpty { cmd = "\(home)/.local/bin/herdr-app do pane.focus --terminal \(terminal); " + cmd }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", cmd]
    try? p.run()
}

// Text sits on a baseline, so frames are given by their vertical centre to keep rows optically aligned.
func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor,
           x: CGFloat, midY: CGFloat, width: CGFloat, kern: CGFloat = 0, center: Bool = false) -> NSTextField {
    let para = NSMutableParagraphStyle()
    para.alignment = center ? .center : .left
    para.lineBreakMode = .byTruncatingTail
    let font = NSFont.systemFont(ofSize: size * k, weight: weight)
    let l = NSTextField(labelWithAttributedString: NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: color, .kern: kern * k, .paragraphStyle: para,
    ]))
    let h = ceil(font.ascender - font.descender + font.leading) + 2
    l.frame = NSRect(x: x, y: midY - h / 2, width: width, height: h)
    return l
}

final class CardView: NSView {
    let item: Item
    let onDismiss: () -> Void
    static var size: NSSize { NSSize(width: 600 * k, height: 112 * k) }

    init(item: Item, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
        super.init(frame: NSRect(origin: .zero, size: CardView.size))
        wantsLayer = true
        let tint = item.needs ? amber : mint
        let w = CardView.size.width, h = CardView.size.height
        let pad = 28 * k

        layer?.backgroundColor = surface.cgColor
        layer?.cornerRadius = 28 * k
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 34 * k
        layer?.shadowOffset = CGSize(width: 0, height: -10 * k)

        let chipS = 60 * k
        let chip = NSView(frame: NSRect(x: pad, y: (h - chipS) / 2, width: chipS, height: chipS))
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 19 * k
        chip.layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = tint.withAlphaComponent(0.30).cgColor
        chip.addSubview(label(item.needs ? "!" : "\u{2713}", 28, .semibold, tint, x: 0, midY: chipS / 2, width: chipS, center: true))
        addSubview(chip)

        let tx = pad + chipS + 22 * k
        let pillW = 96 * k, pillH = 38 * k
        let tw = w - tx - pillW - pad - 18 * k
        addSubview(label(item.project, 22, .semibold, ink, x: tx, midY: h / 2 + 27 * k, width: tw))
        addSubview(label(item.needs ? "Needs your input" : "Finished, ready for review", 15, .medium, tint, x: tx, midY: h / 2 + 0 * k, width: tw))
        let detail = item.needs ? item.body : "Click to jump back in"
        addSubview(label(detail, 13, .regular, NSColor(white: 1, alpha: 0.48), x: tx, midY: h / 2 - 26 * k, width: tw))

        let pill = NSView(frame: NSRect(x: w - pad - pillW, y: (h - pillH) / 2, width: pillW, height: pillH))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = pillH / 2
        pill.layer?.backgroundColor = tint.cgColor
        pill.addSubview(label("Open", 14, .semibold, inkDark, x: 0, midY: pillH / 2, width: pillW, center: true))
        addSubview(pill)
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        openHerdr(terminal: item.terminal)
        onDismiss()
    }
}

final class CoverView: NSView {
    let onBackdrop: () -> Void

    init(frame: NSRect, items: [Item], showCards: Bool, onDismissItem: @escaping (Item) -> Void, onBackdrop: @escaping () -> Void) {
        self.onBackdrop = onBackdrop
        super.init(frame: frame)
        wantsLayer = true

        let blur = NSVisualEffectView(frame: bounds)
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        // a view (not a sublayer) so it draws above the blur and the work underneath stays hidden
        let base = NSView(frame: bounds)
        base.wantsLayer = true
        base.layer?.backgroundColor = bgDeep.withAlphaComponent(0.97).cgColor
        base.autoresizingMask = [.width, .height]
        addSubview(base)

        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = bounds
        glow.colors = [bgGlow.withAlphaComponent(0.85).cgColor, bgGlow.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.52)
        glow.endPoint = CGPoint(x: 1.0, y: 1.1)
        base.layer?.addSublayer(glow)

        let cx = bounds.midX
        addSubview(label("Click anywhere outside the cards to dismiss", 13, .regular, NSColor(white: 1, alpha: 0.30),
                         x: cx - 400 * k, midY: 56 * k, width: 800 * k, center: true))

        guard showCards else { return }
        let gap = 18 * k
        let cw = CardView.size.width, ch = CardView.size.height
        let cardsH = CGFloat(items.count) * ch + CGFloat(items.count - 1) * gap
        let headerH = 168 * k
        let blockH = headerH + cardsH
        let top = bounds.midY + blockH / 2 + 24 * k

        let needs = items.contains { $0.needs }
        let tint = needs ? amber : mint
        let hw = 900 * k, hx = cx - hw / 2
        addSubview(label("CLAUDE CODE", 13, .semibold, tint.withAlphaComponent(0.9), x: hx, midY: top - 10 * k, width: hw, kern: 3.5, center: true))
        let headline = items.count == 1 ? items[0].title : "\(items.count) sessions are waiting"
        addSubview(label(headline, 50, .semibold, ink, x: hx, midY: top - 66 * k, width: hw, center: true))
        addSubview(label("Pick one to jump straight to it in Herdr.", 17, .regular, NSColor(white: 1, alpha: 0.5),
                         x: hx, midY: top - 122 * k, width: hw, center: true))

        for (i, item) in items.enumerated() {
            let card = CardView(item: item) { onDismissItem(item) }
            card.frame.origin = NSPoint(x: cx - cw / 2, y: top - headerH - ch - CGFloat(i) * (ch + gap))
            addSubview(card)
        }
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onBackdrop() }
}

func makePanel(frame: NSRect) -> NSPanel {
    let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .screenSaver
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    return p
}

final class App: NSObject, NSApplicationDelegate {
    var panels: [NSPanel] = []
    var signature = ""
    var idleTicks = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func clearAll() {
        for i in loadItems() { try? FileManager.default.removeItem(atPath: i.path) }
    }

    func tick() {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == herdrId && ProcessInfo.processInfo.environment["NOTIFY_FLASH_KEEP"] == nil { clearAll() }
        let items = loadItems()
        if items.isEmpty {
            idleTicks += 1
            panels.forEach { $0.orderOut(nil) }
            panels = []
            signature = ""
            if idleTicks > 8 { NSApp.terminate(nil) }
            return
        }
        idleTicks = 0
        let sig = items.map { "\($0.path)\($0.time)" }.joined()
        if sig != signature { signature = sig; rebuild(items) }
    }

    func rebuild(_ items: [Item]) {
        let wasShowing = !panels.isEmpty
        panels.forEach { $0.orderOut(nil) }
        let main = NSScreen.main ?? NSScreen.screens[0]
        panels = NSScreen.screens.map { s in
            let p = makePanel(frame: s.frame)
            p.contentView = CoverView(
                frame: NSRect(origin: .zero, size: s.frame.size), items: items, showCards: s == main,
                onDismissItem: { [weak self] _ in self?.clearAll(); self?.tick() },
                onBackdrop: { [weak self] in self?.clearAll(); self?.tick() })
            p.setFrame(s.frame, display: true)
            p.alphaValue = wasShowing ? 1 : 0
            p.orderFrontRegardless()
            if !wasShowing { NSAnimationContext.runAnimationGroup { c in c.duration = 0.4; p.animator().alphaValue = 1 } }
            return p
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
