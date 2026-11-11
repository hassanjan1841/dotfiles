// notify-flash: Claude Code alerts as small cards stacked in the top right, one per session.
// Cards live as JSON files in ~/.config/claude-notify/queue (written by bin/claude-notify).
// Click a card: Herdr opens on that terminal and every card clears. The x dismisses one. Herdr in front: all clear.
// Colours follow dark-theme guidance: off-white text on dark gray (no pure black or white), desaturated accents.
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let queueDir = "\(home)/.config/claude-notify/queue"
let herdrId = "dev.herdr.app"
let maxAge: TimeInterval = 3 * 3600

let k: CGFloat = {
    let w = (NSScreen.main ?? NSScreen.screens[0]).frame.width
    return min(1.3, max(1.0, w / 1900))
}()

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}
let surface = rgb(28, 31, 38)
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

func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor,
           x: CGFloat, midY: CGFloat, width: CGFloat, center: Bool = false) -> NSTextField {
    let para = NSMutableParagraphStyle()
    para.alignment = center ? .center : .left
    para.lineBreakMode = .byTruncatingTail
    let font = NSFont.systemFont(ofSize: size * k, weight: weight)
    let l = NSTextField(labelWithAttributedString: NSAttributedString(string: s, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: para,
    ]))
    let h = ceil(font.ascender - font.descender + font.leading) + 2
    l.frame = NSRect(x: x, y: midY - h / 2, width: width, height: h)
    return l
}

final class CardView: NSView {
    let item: Item
    let onDismiss: () -> Void
    let onOpen: () -> Void
    static var size: NSSize { NSSize(width: 400 * k, height: 84 * k) }

    init(item: Item, onDismiss: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
        self.onOpen = onOpen
        super.init(frame: NSRect(origin: .zero, size: CardView.size))
        wantsLayer = true
        let tint = item.needs ? amber : mint
        let w = CardView.size.width, h = CardView.size.height

        layer?.backgroundColor = surface.cgColor
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 18 * k
        layer?.shadowOffset = CGSize(width: 0, height: -6 * k)

        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 4 * k, height: h))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = tint.cgColor
        addSubview(bar)

        let tx = 24 * k
        let pillW = 70 * k, pillH = 30 * k
        let tw = w - tx - pillW - 44 * k
        addSubview(label(item.project, 17, .semibold, ink, x: tx, midY: h / 2 + 18 * k, width: tw))
        addSubview(label(item.needs ? "Needs your input" : "Finished, ready for review", 13, .medium, tint, x: tx, midY: h / 2 - 2 * k, width: tw))
        let detail = item.needs ? item.body : "Click to jump back in"
        addSubview(label(detail, 11, .regular, NSColor(white: 1, alpha: 0.45), x: tx, midY: h / 2 - 22 * k, width: tw))

        let pill = NSView(frame: NSRect(x: w - 30 * k - pillW, y: (h - pillH) / 2, width: pillW, height: pillH))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 3
        pill.layer?.backgroundColor = tint.cgColor
        pill.addSubview(label("Open", 12, .semibold, inkDark, x: 0, midY: pillH / 2, width: pillW, center: true))
        addSubview(pill)

        addSubview(label("\u{2715}", 10, .bold, NSColor(white: 1, alpha: 0.35), x: w - 22 * k, midY: h - 14 * k, width: 14 * k, center: true))
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x > bounds.width - 34 * k && p.y > bounds.height - 30 * k { onDismiss(); return }
        openHerdr(terminal: item.terminal)
        onOpen()
    }
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
    var panel: NSPanel?
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
        let keep = ProcessInfo.processInfo.environment["NOTIFY_FLASH_KEEP"] != nil
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == herdrId && !keep { clearAll() }
        let items = loadItems()
        if items.isEmpty {
            idleTicks += 1
            panel?.orderOut(nil)
            panel = nil
            signature = ""
            if idleTicks > 8 { NSApp.terminate(nil) }
            return
        }
        idleTicks = 0
        let sig = items.map { "\($0.path)\($0.time)" }.joined()
        if sig != signature { signature = sig; rebuild(items) }
    }

    func rebuild(_ items: [Item]) {
        let wasShowing = panel != nil
        panel?.orderOut(nil)
        let gap = 10 * k, margin = 20 * k, pad = 28 * k
        let cw = CardView.size.width, ch = CardView.size.height
        let total = CGFloat(items.count) * ch + CGFloat(items.count - 1) * gap
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let frame = NSRect(x: vf.maxX - cw - margin - pad, y: vf.maxY - total - margin - pad, width: cw + pad * 2, height: total + pad * 2)
        let p = makePanel(frame: frame)
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        for (i, item) in items.enumerated() {
            let card = CardView(item: item,
                                onDismiss: { [weak self] in try? FileManager.default.removeItem(atPath: item.path); self?.tick() },
                                onOpen: { [weak self] in self?.clearAll(); self?.tick() })
            card.frame.origin = NSPoint(x: pad, y: pad + total - ch - CGFloat(i) * (ch + gap))
            root.addSubview(card)
        }
        p.contentView = root
        p.setFrame(frame, display: true)
        p.alphaValue = wasShowing ? 1 : 0
        p.orderFrontRegardless()
        if !wasShowing { NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; p.animator().alphaValue = 1 } }
        panel = p
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
