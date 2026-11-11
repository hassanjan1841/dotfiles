// notify-flash: Claude Code alerts as small cards stacked in the top right, one per Herdr terminal.
// A hook (bin/claude-notify) drops a marker file per finished or blocked session; Herdr's own status for that
// terminal decides whether the card shows. Working again, gone, or you went to Herdr: the card goes away.
// Click a card: Herdr opens on that terminal. The x dismisses one.
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
    let title, status, detail: String
    let needs: Bool
    let terminal: String
    let time: Double
}

struct Agent { let status: String?; let tab: String; let space: String }

/// Herdr's own view of every terminal: its agent status and where it lives.
func herdrAgents() -> [String: Agent]? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "\(home)/.local/bin/herdr-app")
    p.arguments = ["ls"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let spaces = j["spaces"] as? [[String: Any]] else { return nil }
    var out: [String: Agent] = [:]
    for sp in spaces {
        let spaceName = sp["name"] as? String ?? ""
        for tab in (sp["tabs"] as? [[String: Any]]) ?? [] {
            let tabName = tab["name"] as? String ?? ""
            for t in (tab["terminals"] as? [[String: Any]]) ?? [] {
                guard let id = t["terminal"] as? String else { continue }
                out[id] = Agent(status: t["status"] as? String, tab: tabName, space: spaceName)
            }
        }
    }
    return out
}

func isNumber(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0.isNumber } }

func removeMarker(_ path: String) { try? FileManager.default.removeItem(atPath: path) }

/// Markers whose Herdr status says the session is really waiting on you, newest first.
func loadItems(agents: [String: Agent]?) -> [Item] {
    let now = Date().timeIntervalSince1970
    let names = (try? FileManager.default.contentsOfDirectory(atPath: queueDir)) ?? []
    var items: [Item] = []
    for n in names where n.hasSuffix(".json") {
        let path = "\(queueDir)/\(n)"
        guard let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { removeMarker(path); continue }
        let t = (j["time"] as? Double) ?? 0
        let terminal = j["terminal"] as? String ?? ""
        if now - t > maxAge { removeMarker(path); continue }

        if (j["test"] as? Bool) == true {
            let needs = (j["kind"] as? String) == "needs"
            items.append(Item(path: path, title: j["title"] as? String ?? "Test card", status: needs ? "Needs your input" : "Finished, ready for review",
                              detail: j["message"] as? String ?? "", needs: needs, terminal: "", time: t))
            continue
        }

        guard let agents = agents else { continue }
        guard let agent = agents[terminal] else { removeMarker(path); continue }
        let status = agent.status ?? ""
        // the Stop hook can fire a moment before Herdr flips the status, so a fresh marker is given a few seconds
        if status == "working" {
            if now - t > 6 { removeMarker(path) }
            continue
        }
        let needs = status == "blocked"
        let title = (agent.tab.isEmpty || isNumber(agent.tab)) ? agent.space : agent.tab
        let message = (j["message"] as? String) ?? ""
        let place = title == agent.space && !agent.tab.isEmpty ? "Tab \(agent.tab)" : agent.space
        let detail = needs ? (message.isEmpty ? "Waiting for your approval" : message) : place
        items.append(Item(path: path, title: title, status: needs ? "Needs your input" : "Finished, ready for review",
                          detail: detail, needs: needs, terminal: terminal, time: t))
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
        addSubview(label(item.title, 17, .semibold, ink, x: tx, midY: h / 2 + 18 * k, width: tw))
        addSubview(label(item.status, 13, .medium, tint, x: tx, midY: h / 2 - 2 * k, width: tw))
        addSubview(label(item.detail, 11, .regular, NSColor(white: 1, alpha: 0.45), x: tx, midY: h / 2 - 22 * k, width: tw))

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
    var announced = Set<String>()
    var agents: [String: Agent]?
    var tickCount = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func clearAll() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: queueDir)) ?? []
        for n in names where n.hasSuffix(".json") { removeMarker("\(queueDir)/\(n)") }
    }

    func tick() {
        let keep = ProcessInfo.processInfo.environment["NOTIFY_FLASH_KEEP"] != nil
        // going to Herdr counts as having seen everything
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == herdrId && !keep { clearAll() }
        tickCount += 1
        if tickCount % 2 == 1 || agents == nil { agents = herdrAgents() }
        let items = loadItems(agents: agents)
        if items.isEmpty {
            idleTicks += 1
            panel?.orderOut(nil)
            panel = nil
            signature = ""
            if idleTicks > 60 { NSApp.terminate(nil) }
            return
        }
        idleTicks = 0
        for i in items where !announced.contains("\(i.path)\(i.time)") {
            announced.insert("\(i.path)\(i.time)")
            let name = i.needs ? "Sosumi" : "Glass"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            p.arguments = ["/System/Library/Sounds/\(name).aiff"]
            try? p.run()
        }
        let sig = items.map { "\($0.path)\($0.time)\($0.needs)" }.joined()
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
                                onDismiss: { [weak self] in removeMarker(item.path); self?.tick() },
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
