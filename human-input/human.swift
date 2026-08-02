import AppKit
import ApplicationServices
import IOKit.hid
import Vision

// Declared rather than importing all of Carbon, whose namespace collides with names
// used here. Secure input is what a password field turns on to block synthetic keys.
@_silgen_name("IsSecureEventInputEnabled")
func IsSecureEventInputEnabled() -> Bool
import CoreGraphics
import Foundation

// A human-input layer for macOS: every pointer path, click dwell, scroll ramp and
// keystroke gap is sampled from the way a hand actually behaves, so automated work
// does not read as a fixed-interval machine.
//
// Pointer moves work with no special permission. Clicks, scrolls and keystrokes are
// synthetic input events and need Accessibility permission for the parent terminal.

// ============================================================================
// Foundations
// ============================================================================

let screen = CGDisplayBounds(CGMainDisplayID())
let keySource = CGEventSource(stateID: .privateState)

/// One person's hand and rhythm, kept consistent by name. Randomness alone makes a
/// different person every run, which is its own kind of tell.
struct Traits {
    var pace = 1.0
    var bowBias = 0.5
    var tremor = 1.0
    var errorScale = 1.0
    var wpm = 70.0
}

var traits = Traits()

func personaTraits(_ name: String) -> Traits {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
    func next(_ lo: Double, _ hi: Double) -> Double {
        h ^= h >> 33; h = h &* 0xff51_afd7_ed55_8ccd; h ^= h >> 29
        return lo + (hi - lo) * Double(h % 10_000) / 10_000
    }
    return Traits(pace: next(0.82, 1.22), bowBias: next(0.15, 0.85), tremor: next(0.6, 1.5),
                  errorScale: next(0.5, 1.7), wpm: next(52, 88))
}

let startedAt = Date()

/// People warm up and then tire, and both show up as speed.
func drift() -> Double {
    let mins = Date().timeIntervalSince(startedAt) / 60
    if mins < 0.5 { return 1.06 }
    if mins < 15 { return 1.0 }
    return min(1.0 + (mins - 15) * 0.005, 1.18)
}

func cursor() -> CGPoint {
    CGEvent(source: nil)?.location ?? CGPoint(x: screen.midX, y: screen.midY)
}

var dryElapsed = 0.0
var dry = false

/// Held button, so an abort mid-drag can let go instead of leaving the mouse down.
var buttonHeld: (CGMouseButton, CGPoint)?
let stopFile = NSHomeDirectory() + "/.human-stop"
var lastPanicCheck = Date.distantPast

/// Hold control+option+command, or touch ~/.human-stop, and everything stops.
func panicCheck() {
    guard !dry, Date().timeIntervalSince(lastPanicCheck) > 0.05 else { return }
    lastPanicCheck = Date()
    let held = CGEventSource.flagsState(.combinedSessionState)
    let combo: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    guard held.contains(combo) || FileManager.default.fileExists(atPath: stopFile) else { return }
    if let (b, p) = buttonHeld {
        postMouse(b == .right ? .rightMouseUp : .leftMouseUp, p, b)
    }
    FileHandle.standardError.write("human: stopped\n".data(using: .utf8)!)
    exit(5)
}

func nap(_ seconds: Double) {
    // Rehearsals add up the intended delays instead of living through them, so a run
    // can be checked, and speed calibrated, without touching the machine.
    if dry { dryElapsed += max(0, seconds); return }
    panicCheck()
    Thread.sleep(forTimeInterval: max(0, seconds))
}

func dist(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(b.x - a.x, b.y - a.y)) }

func onScreen(_ p: CGPoint, inset: CGFloat = 2) -> CGPoint {
    CGPoint(x: min(max(p.x, screen.minX + inset), screen.maxX - inset),
            y: min(max(p.y, screen.minY + inset), screen.maxY - inset))
}

var lastPosted: CGPoint?

/// A real mouse reports whole pixels, carries the delta it travelled, and sends
/// nothing at all when it has not moved. Sub-pixel interpolation on a smooth clock is
/// the single biggest reason synthetic motion reads as an animation.
func warp(_ p: CGPoint) {
    if dry { return }
    let q = onScreen(CGPoint(x: p.x.rounded(), y: p.y.rounded()))
    let from = lastPosted ?? cursor()
    if q == from { return }
    // Deltas are deliberately not set. With an absolute cursor position the system
    // applies pointer acceleration on top of the warp, and the cursor visibly fights
    // itself. Whole pixels and an honest polling rate are what matter here.
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: q, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    lastPosted = q
}

/// Minimum-jerk profile: the velocity curve a human arm follows, slow at both ends
/// and fastest mid-flight. Linear interpolation is the giveaway that it is a machine.
func minJerk(_ t: Double) -> Double {
    let t3 = t * t * t
    return t3 * (10 - 15 * t + 6 * t * t)
}

func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                   y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

/// Reaction gap between two deliberate actions.
func beat(_ scale: Double = 1) {
    nap(Double.random(in: 0.09...0.34) * scale)
}

var trusted: Bool { AXIsProcessTrusted() }

func requireTrust(_ what: String) {
    guard !trusted, !dry else { return }
    FileHandle.standardError.write("""
    human: \(what) needs Accessibility permission.
      System Settings > Privacy & Security > Accessibility > enable your terminal app,
      then run `human check` again. Pointer moves work without it.

    """.data(using: .utf8)!)
    exit(3)
}

// ============================================================================
// Focus guard
//
// The real hazard of synthetic input is not a bad pixel, it is a keystroke landing
// in whatever window happens to be in front. Anything that types or clicks can be
// pinned to an app, and refuses to fire if that app is not the one in front.
// ============================================================================

func frontmostApp() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
}

func focusApp(_ name: String, timeout: Double = 12) -> Bool {
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
        app.activate(options: [.activateAllWindows])
    } else {
        // Not running yet, so it has to be launched. A name is not a bundle id, so look
        // where apps live before falling back to letting the system resolve it.
        let candidates = ["/Applications/\(name).app", "/System/Applications/\(name).app",
                          "/System/Applications/Utilities/\(name).app",
                          NSHomeDirectory() + "/Applications/\(name).app"]
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", name]
            try? task.run()
            task.waitUntilExit()
        }
    }
    // NSWorkspace only learns about the switch through notifications, so the run loop
    // has to be pumped while waiting or frontmostApplication never changes here.
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        if frontmostApp() == name { nap(Double.random(in: 0.25...0.6)); return true }
    }
    return frontmostApp() == name
}

var requiredApp: String?

func enforceFocus(_ what: String) {
    guard let want = requiredApp, !dry else { return }
    let have = frontmostApp()
    guard have != want else { return }
    FileHandle.standardError.write(
        "human: refusing to \(what), '\(want)' must be frontmost but '\(have)' is\n".data(using: .utf8)!)
    exit(4)
}

// ============================================================================
// Sight
//
// Native apps publish their whole interface through the Accessibility tree: every
// button, field and label, with an exact rectangle. Reading that beats matching
// pixels, which is slow, breaks on themes and scaling, and needs another permission.
// ============================================================================

struct Seen {
    let role: String
    let subrole: String
    let label: String
    let rect: CGRect
    let depth: Int
    var centre: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    /// What to call it when it has no label of its own: AXCloseButton reads as "close".
    var name: String {
        if !label.isEmpty { return label }
        let r = subrole.isEmpty ? role : subrole
        return r.hasPrefix("AX") ? String(r.dropFirst(2)) : r
    }
}

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axText(_ el: AXUIElement, _ attr: String) -> String? {
    guard let v = axValue(el, attr), CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
    let s = (v as! CFString) as String
    return s.isEmpty ? nil : s
}

func axRect(_ el: AXUIElement) -> CGRect? {
    guard let pv = axValue(el, kAXPositionAttribute as String), CFGetTypeID(pv) == AXValueGetTypeID(),
          let sv = axValue(el, kAXSizeAttribute as String), CFGetTypeID(sv) == AXValueGetTypeID()
    else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(pv as! AXValue, .cgPoint, &pos),
          AXValueGetValue(sv as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: pos, size: size)
}

/// Everything a person could read off an element: its title, its spoken description,
/// its placeholder, its help text. Its contents count too, but only when short enough
/// to be a name. A text area's value is the whole document, which names nothing.
func axLabel(_ el: AXUIElement) -> String {
    for attr in [kAXTitleAttribute, kAXDescriptionAttribute,
                 kAXPlaceholderValueAttribute, kAXHelpAttribute] {
        if let s = axText(el, attr as String) { return s }
    }
    if let v = axText(el, kAXValueAttribute as String), v.count <= 80 { return v }
    if let id = axText(el, kAXIdentifierAttribute as String), !id.hasPrefix("_NS:") { return id }
    return ""
}

func axTree(_ root: AXUIElement, limit: Int = 4000, maxDepth: Int = 24) -> [Seen] {
    var out: [Seen] = []
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    while let (el, depth) = stack.popLast(), out.count < limit {
        if depth > maxDepth { continue }
        let role = axText(el, kAXRoleAttribute as String) ?? "?"
        let subrole = axText(el, kAXSubroleAttribute as String) ?? ""
        if let r = axRect(el), r.width > 0, r.height > 0 {
            out.append(Seen(role: role, subrole: subrole, label: axLabel(el), rect: r, depth: depth))
        }
        if let kids = axValue(el, kAXChildrenAttribute as String) as? [AXUIElement] {
            for kid in kids { stack.append((kid, depth + 1)) }
        }
    }
    return out
}

func axRoot(_ appName: String?) -> AXUIElement? {
    let name = appName ?? frontmostApp()
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })
    else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

/// Roles worth clicking. Everything else is scenery unless asked for by name.
let clickableRoles: Set<String> = [
    "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
    "AXTextField", "AXTextArea", "AXLink", "AXMenuItem", "AXTab", "AXSlider",
    "AXComboBox", "AXSearchField", "AXCell", "AXRow", "AXImage", "AXStaticText",
    "AXDisclosureTriangle", "AXIncrementor", "AXToolbar", "AXScrollBar"
]

func matches(_ s: Seen, needle: String, role: String?) -> Int? {
    if let want = role, s.role.lowercased() != want.lowercased() { return nil }
    guard !needle.isEmpty else { return role == nil ? nil : 1000 }
    let n = needle.lowercased()
    var best: Int?
    for hay in [s.label.lowercased(), s.name.lowercased(), s.subrole.lowercased()] where !hay.isEmpty {
        let score = hay == n ? 0 : hay.hasPrefix(n) ? 1 : hay.contains(n) ? 2 : nil
        if let sc = score, sc < (best ?? 99) { best = sc }
    }
    return best
}

var useOCR = false
var ocrFast = false

func find(_ needle: String, app: String?, role: String?, all: Bool) -> [Seen] {
    var seen: [Seen] = []
    if let root = axRoot(app) { seen = axTree(root) }
    // Only reach for pixels when the tree cannot answer: it is slower and fallible.
    if useOCR && seen.allSatisfy({ matches($0, needle: needle, role: role) == nil }) {
        seen += ocrRead(screen, fast: ocrFast)
    }
    var scored: [(Int, Seen)] = []
    for s in seen {
        guard let score = matches(s, needle: needle, role: role) else { continue }
        // Prefer something you could actually click, and prefer smaller, more specific
        // elements over the giant containers that happen to hold the same text.
        let bonus = clickableRoles.contains(s.role) ? 0 : 4
        let area = Int(s.rect.width * s.rect.height / 1000)
        scored.append((score * 100 + bonus * 10 + min(area, 9), s))
    }
    scored.sort { $0.0 < $1.0 }
    return all ? scored.map { $0.1 } : Array(scored.prefix(1).map { $0.1 })
}

// ============================================================================
// Terminal panes
//
// WezTerm publishes nothing to the accessibility tree because it draws on the GPU,
// but its own CLI hands over the exact text of any pane and writes into it without
// focus or synthetic input. Exact beats recognised, so this is preferred over OCR
// whenever the target is a terminal.
// ============================================================================

@discardableResult
func run(_ tool: String, _ args: [String]) -> (out: String, code: Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return ("", 127) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
}

let weztermPath = ["/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

func requireWezterm() -> String {
    guard let path = weztermPath else {
        FileHandle.standardError.write("human: wezterm cli not found\n".data(using: .utf8)!)
        exit(2)
    }
    return path
}

func paneText(_ id: String) -> String {
    run(requireWezterm(), ["cli", "get-text", "--pane-id", id]).out
}

func paneMatches(_ text: String, _ pattern: String) -> Bool {
    if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
        let range = NSRange(text.startIndex..., in: text)
        return re.firstMatch(in: text, range: range) != nil
    }
    return text.localizedCaseInsensitiveContains(pattern)
}

// ============================================================================
// Pixel eyes
//
// The fallback for anything that publishes no accessibility tree: terminals drawing
// on the GPU, canvases, games, screen shares. Slower and fallible where the tree is
// exact, so it is only used when asked for or when the tree turns up nothing.
// ============================================================================

func captureScreen(_ region: CGRect) -> (CGImage, CGFloat)? {
    // screencapture rather than the framework: CGDisplayCreateImage is gone in current
    // macOS and ScreenCaptureKit is an async stream API, awkward for a one-shot tool.
    let tmp = NSTemporaryDirectory() + "human-ocr.png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-R",
                   "\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))", tmp]
    try? p.run()
    p.waitUntilExit()
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return (img, CGFloat(img.width) / max(region.width, 1))     // retina factor
}

func ocrRead(_ region: CGRect, fast: Bool) -> [Seen] {
    guard let (img, scale) = captureScreen(region) else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = fast ? .fast : .accurate
    request.usesLanguageCorrection = false      // UI text is not prose; do not "fix" it
    try? VNImageRequestHandler(cgImage: img).perform([request])

    return (request.results ?? []).compactMap { line in
        guard let best = line.topCandidates(1).first else { return nil }
        // Vision normalises with the origin at the bottom left; screens count downward.
        let b = line.boundingBox
        let w = CGFloat(img.width) / scale, h = CGFloat(img.height) / scale
        let rect = CGRect(x: region.minX + b.minX * w,
                          y: region.minY + (1 - b.maxY) * h,
                          width: b.width * w, height: b.height * h)
        return Seen(role: "AXOCRText", subrole: "", label: best.string, rect: rect, depth: 0)
    }
}

// ============================================================================
// Pointer
// ============================================================================

/// One ballistic submovement. Curved, eased, and wobbling the way a hand does.
func submove(from start: CGPoint, to end: CGPoint, width: Double, primary: Bool) {
    let d = dist(start, end)
    if d < 0.6 { return }

    // Fitts' law with the target's width, not just the distance: a small target is
    // approached more carefully than a big one the same distance away.
    // Fitts' law predicts the time for the WHOLE aimed movement, corrections included.
    // Spending the full budget on the throw alone and then adding corrections on top
    // makes every move about twice as slow as a person, and slow smooth motion is
    // precisely what reads as an animation.
    let difficulty = log2(2 * d / max(width, 2) + 1)
    var duration = (0.035 + 0.062 * difficulty) * Double.random(in: 0.82...1.3) * traits.pace * drift()
    duration = min(max(duration, 0.035), 1.0)

    let dx = end.x - start.x, dy = end.y - start.y
    let len = max(CGFloat(d), 1)
    let nx = -dy / len, ny = dx / len

    // A hand sweeps, and it tends to sweep the same way each time.
    let bowSign: Double = Double.random(in: 0...1) < traits.bowBias ? 1 : -1
    let bow = CGFloat(d * Double.random(in: 0.02...0.10) * bowSign)
    let c1 = onScreen(CGPoint(x: start.x + dx * 0.28 + nx * bow, y: start.y + dy * 0.28 + ny * bow))
    let c2 = onScreen(CGPoint(x: start.x + dx * 0.72 + nx * bow * 0.7,
                              y: start.y + dy * 0.72 + ny * bow * 0.7))

    // Physiological tremor sits at 8-12Hz and is tiny; the wrist drifts underneath it
    // at 1-3Hz and wider. Both are frequencies in real seconds, not in path progress,
    // which is what makes them read as a hand rather than a decorative wave.
    let tremorHz = Double.random(in: 8...12), tremorPhase = Double.random(in: 0...(2 * Double.pi))
    let driftHz = Double.random(in: 1.1...2.8), driftPhase = Double.random(in: 0...(2 * Double.pi))
    let tremorAmp = Double.random(in: 0.2...0.6) * traits.tremor
    let driftAmp = min(0.8 + 0.011 * d, 5.5) * traits.tremor

    // An ordinary mouse polls at 125Hz. The interval stays put and the deltas vary,
    // which is the opposite of easing a smooth curve on a jittery clock.
    let poll = 0.008
    let steps = max(4, Int(duration / poll))

    // Motor noise: the rate of travel wanders smoothly, so the velocity curve is a bell
    // with a wobble in it rather than a textbook curve. The rate stays positive, so
    // progress never goes backwards, which is what made the earlier attempt stutter.
    let noiseA = Double.random(in: 1.5...3.5), noisePhaseA = Double.random(in: 0...(2 * Double.pi))
    let noiseB = Double.random(in: 4...7), noisePhaseB = Double.random(in: 0...(2 * Double.pi))
    var rates: [Double] = []
    for i in 0..<steps {
        let at = Double(i) / Double(steps) * duration
        rates.append(max(0.3, 1 + 0.14 * sin(2 * Double.pi * noiseA * at + noisePhaseA)
                              + 0.07 * sin(2 * Double.pi * noiseB * at + noisePhaseB)))
    }
    let rateTotal = rates.reduce(0, +)

    // Aimed movement is not symmetric. It accelerates hard and spends longer slowing
    // down, peaking around 40% of the way through. A symmetric bell is the tell that
    // something was tweened rather than thrown.
    let skew = Double.random(in: 0.78...0.9)
    var travelled = 0.0
    let begin = Date()
    // A long reach sometimes stalls partway while the eyes catch up.
    let hesitateAt = (primary && d > 260 && Double.random(in: 0...1) < 0.22)
        ? Int(Double(steps) * Double.random(in: 0.35...0.7)) : -1

    for i in 1...steps {
        // Progress only ever goes forward, but not at a constant rate: the wandering
        // rate is what puts a wobble on the velocity curve.
        travelled += rates[i - 1]
        let progress = travelled / rateTotal
        let eased = minJerk(pow(progress, skew))
        let clock = progress * duration
        var p = bezier(start, c1, c2, end, CGFloat(eased))
        let taper = sin(Double.pi * eased)
        let wobble = taper * (driftAmp * sin(2 * Double.pi * driftHz * clock + driftPhase)
            + tremorAmp * sin(2 * Double.pi * tremorHz * clock + tremorPhase))
        p.x += nx * CGFloat(wobble)
        p.y += ny * CGFloat(wobble)
        warp(p)
        if i == hesitateAt { nap(Double.random(in: 0.05...0.19)) }
        // Sleeping for 8ms actually takes about 10 on macOS, so pacing by sleep alone
        // stretches every movement by a quarter. Aim at a deadline instead.
        if dry {
            nap(poll)
        } else {
            let due = begin.addingTimeInterval(duration * Double(i) / Double(steps))
            let wait = due.timeIntervalSinceNow
            if wait > 0 { nap(wait * Double.random(in: 0.9...1.1)) }
        }
    }
}

/// Aimed movement is not one smooth sweep to the exact pixel. It is a fast throw that
/// lands near the target, then one or two smaller corrections that close the gap, and
/// the miss grows with the distance thrown. That structure is what reads as a person.
func moveTo(_ target: CGPoint, width: Double = 26) {
    if dist(cursor(), target) < 1 { return }
    let close = max(width * 0.3, 1.6)

    for attempt in 0..<3 {
        let here = cursor()
        let gap = dist(here, target)
        if gap <= close { break }

        let coverage = attempt == 0 ? Double.random(in: 0.84...1.04) : Double.random(in: 0.55...1.1)
        let sigma = 0.012 * gap + 0.6                    // motor noise scales with the throw
        let aim = CGPoint(x: here.x + (target.x - here.x) * CGFloat(coverage) + CGFloat(gauss() * sigma),
                          y: here.y + (target.y - here.y) * CGFloat(coverage) + CGFloat(gauss() * sigma))
        submove(from: here, to: onScreen(aim), width: width, primary: attempt == 0)
        // Corrections do not always pause first; sometimes they run straight on.
        if dist(cursor(), target) > close && Double.random(in: 0...1) < 0.6 {
            nap(Double.random(in: 0.03...0.11))
        }
    }

    // Close enough is close enough. A person does not spend another submovement
    // travelling two pixels, and inside a target it makes no difference anyway.
    if dist(cursor(), target) > 2.5 {
        submove(from: cursor(), to: target, width: width, primary: false)
    }
    // Settle rather than snap. A hand does not stop dead on a pixel.
    // Hovering before acting is one of the clearest human tells; a bot converges and
    // fires. Hold near the target for a moment, tremor still running.
    let hover = Double.random(in: 0.02...0.12)
    let held = cursor()
    var t = 0.0
    let hz = Double.random(in: 8...12), ph = Double.random(in: 0...(2 * Double.pi))
    while t < hover {
        warp(CGPoint(x: held.x + CGFloat(0.45 * sin(2 * Double.pi * hz * t + ph) * traits.tremor),
                     y: held.y + CGFloat(0.45 * cos(2 * Double.pi * hz * 0.83 * t + ph) * traits.tremor)))
        nap(0.016)
        t += 0.016
    }
}

/// Nobody lands on the exact centre of a button, and nobody holds perfectly still.
/// Precise mode turns that off for targets too small to miss, like a 4px resize edge.
var precise = false

func aimJitter(_ p: CGPoint, spread: Double = 2.5) -> CGPoint {
    guard !precise else { return p }
    return CGPoint(x: p.x + CGFloat(Double.random(in: -spread...spread)),
                   y: p.y + CGFloat(Double.random(in: -spread...spread)))
}

func postMouse(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton,
               clickState: Int = 1, flags: CGEventFlags = []) {
    if dry { return }
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                          mouseCursorPosition: onScreen(p), mouseButton: button) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
    if !flags.isEmpty { e.flags = flags }
    e.post(tap: .cghidEventTap)
}

func click(at target: CGPoint?, button: CGMouseButton = .left, times: Int = 1,
           modifiers: CGEventFlags = [], holdFor: Double = 0) {
    requireTrust("clicking")
    enforceFocus("clicking")
    if let t = target { moveTo(aimJitter(t)) }

    let down: CGEventType = button == .right ? .rightMouseDown
        : button == .center ? .otherMouseDown : .leftMouseDown
    let up: CGEventType = button == .right ? .rightMouseUp
        : button == .center ? .otherMouseUp : .leftMouseUp

    let held = modifiers.isEmpty ? [] : holdModifiers(modifiers)
    nap(Double.random(in: 0.06...0.22))           // settle before pressing
    for n in 1...max(1, times) {
        let p = n == 1 ? cursor() : aimJitter(cursor(), spread: 1.2)
        postMouse(down, p, button, clickState: n, flags: held)
        buttonHeld = (button, p)
        // A long press is its own gesture: context menus, drag handles, repeat buttons.
        nap(holdFor > 0 ? holdFor : Double.random(in: 0.055...0.135))
        postMouse(up, p, button, clickState: n, flags: held)
        buttonHeld = nil
        if n < times { nap(Double.random(in: 0.07...0.15)) }
    }
    if !held.isEmpty { releaseModifiers(held) }
    beat()
}

func drag(from a: CGPoint, to b: CGPoint) {
    requireTrust("dragging")
    enforceFocus("dragging")
    moveTo(aimJitter(a))
    nap(Double.random(in: 0.08...0.2))
    postMouse(.leftMouseDown, cursor(), .left)
    buttonHeld = (.left, cursor())
    nap(Double.random(in: 0.09...0.24))          // grab before hauling

    // Same curved, eased path as a move, but every step carries the drag event.
    let start = cursor()
    let d = max(dist(start, b), 1)
    let duration = min(max(0.25 + 0.2 * log2(1 + d / 40), 0.3), 2.4) * Double.random(in: 0.85...1.25)
    let steps = max(14, Int(duration / 0.012))
    let dx = b.x - start.x, dy = b.y - start.y
    let nx = -dy / CGFloat(d), ny = dx / CGFloat(d)
    let bow = CGFloat(d) * CGFloat(Double.random(in: 0.03...0.12)) * (Bool.random() ? 1 : -1)
    let c1 = onScreen(CGPoint(x: start.x + dx * 0.3 + nx * bow, y: start.y + dy * 0.3 + ny * bow))
    let c2 = onScreen(CGPoint(x: start.x + dx * 0.7 + nx * bow * 0.5, y: start.y + dy * 0.7 + ny * bow * 0.5))
    for i in 1...steps {
        let t = minJerk(Double(i) / Double(steps))
        var p = bezier(start, c1, c2, b, CGFloat(t))
        p.x += CGFloat(Double.random(in: -0.8...0.8))
        p.y += CGFloat(Double.random(in: -0.8...0.8))
        postMouse(.leftMouseDragged, p, .left)
        nap(duration / Double(steps) * Double.random(in: 0.8...1.25))
    }
    postMouse(.leftMouseDragged, b, .left)
    nap(Double.random(in: 0.08...0.2))           // line it up before letting go
    postMouse(.leftMouseUp, b, .left)
    buttonHeld = nil
    beat()
}

/// Real scrolling arrives as a burst of small deltas that ramp up and trail off,
/// never one large jump. Negative amount scrolls down.
func scroll(_ amount: Int, horizontal: Bool = false, over target: CGPoint? = nil) {
    requireTrust("scrolling")
    enforceFocus("scrolling")
    // The wheel acts on whatever sits under the pointer, so go there first.
    if let t = target { moveTo(aimJitter(t)); nap(Double.random(in: 0.1...0.3)) }
    var remaining = abs(amount)
    let sign = amount < 0 ? -1 : 1
    while remaining > 0 {
        // One flick of the fingers, then a pause before the next.
        let flick = min(remaining, Int.random(in: 60...200))
        remaining -= flick
        let steps = max(6, flick / Int.random(in: 6...14))
        var sent = 0
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let ease = sin(Double.pi * t)                    // ramp up, trail off
            var delta = Int(Double(flick) / Double(steps) * (0.4 + 1.2 * ease))
            delta = max(1, delta)
            if i == steps { delta = max(1, flick - sent) }
            sent += delta
            let drift = Int.random(in: -1...1)               // fingers are never perfectly axial
            let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: Int32(horizontal ? drift : sign * delta),
                            wheel2: Int32(horizontal ? sign * delta : drift), wheel3: 0)
            // Real gestures announce themselves: begin, changing, ended. Bare wheel
            // ticks with no phase are how a script scrolls, not how fingers do.
            e?.setIntegerValueField(.scrollWheelEventScrollPhase,
                                    value: i == 1 ? 1 : i == steps ? 4 : 2)
            if !dry { e?.post(tap: .cghidEventTap) }
            nap(Double.random(in: 0.008...0.02))
        }

        // Fingers lift and the surface keeps coasting, decaying to nothing.
        var coast = Double(flick) * Double.random(in: 0.12...0.32)
        var phase = 1
        while coast > 1 {
            let step = max(1, Int(coast * 0.35))
            let m = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: Int32(horizontal ? 0 : sign * step),
                            wheel2: Int32(horizontal ? sign * step : 0), wheel3: 0)
            m?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(phase))
            if !dry { m?.post(tap: .cghidEventTap) }
            phase = 2
            coast -= Double(step)
            nap(0.016)
        }
        if phase == 2 {
            let end = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: 0, wheel2: 0, wheel3: 0)
            end?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
            if !dry { end?.post(tap: .cghidEventTap) }
        }
        if remaining > 0 { nap(Double.random(in: 0.12...0.5)) }
    }
    beat()
}

// ============================================================================
// Keyboard
// ============================================================================

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
    "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
    "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    "`": 50, "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
    "backspace": 51, "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125,
    "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "forwarddelete": 117, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
    "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
]

enum Accuracy { case clean, human, raw }

let modifierKeys: [(CGEventFlags, CGKeyCode)] = [
    (.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58),
    (.maskControl, 59), (.maskSecondaryFn, 63)
]

/// Fingers land on modifiers one at a time and a beat before the key, and they come
/// off after it. Setting a flag on the key event without ever pressing the modifier
/// is not just unconvincing, it makes held-modifier shortcuts like cmd+tab impossible.
func holdModifiers(_ wanted: CGEventFlags) -> CGEventFlags {
    var active: CGEventFlags = []
    for (flag, code) in modifierKeys where wanted.contains(flag) {
        active.insert(flag)
        // A modifier is a flagsChanged event, not a key press. Sent as a key press the
        // event carries the flag but the system's live modifier state never changes,
        // so anything that asks "is shift down right now" correctly answers no.
        let e = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: true)
        e?.type = .flagsChanged
        e?.flags = active
        if !dry { e?.post(tap: .cghidEventTap) }
        nap(Double.random(in: 0.03...0.09))
    }
    return active
}

func releaseModifiers(_ held: CGEventFlags) {
    var active = held
    for (flag, code) in modifierKeys.reversed() where held.contains(flag) {
        active.remove(flag)
        let e = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)
        e?.type = .flagsChanged
        e?.flags = active
        if !dry { e?.post(tap: .cghidEventTap) }
        nap(Double.random(in: 0.02...0.07))
    }
}

func tapKey(_ code: CGKeyCode, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    if !dry { down?.post(tap: .cghidEventTap) }
    nap(Double.random(in: 0.045...0.11))          // held, not instantaneous
    if !dry { up?.post(tap: .cghidEventTap) }
}

/// "cmd+shift+p" reads the way people say it, and it keeps chords in one argument.
func parseChord(_ spec: String) -> (CGKeyCode, CGEventFlags)? {
    var flags = CGEventFlags()
    var key: String?
    for part in spec.lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "alt", "option": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        case "fn": flags.insert(.maskSecondaryFn)
        default: key = part
        }
    }
    guard let name = key, let code = keyCodes[name] else { return nil }
    return (code, flags)
}

func pressKey(_ spec: String, extra: CGEventFlags, repeats: Int = 1, holdFor: Double = 0) {
    requireTrust("pressing keys")
    enforceFocus("pressing keys")
    guard let (code, chordFlags) = parseChord(spec) else {
        FileHandle.standardError.write("human: unknown key '\(spec)'\n".data(using: .utf8)!)
        exit(2)
    }
    let flags = chordFlags.union(extra)
    let held = holdModifiers(flags)
    if holdFor > 0 {
        // Holding a key down, the way you hold an arrow to run a cursor along a line.
        let down = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: true)
        down?.flags = held
        if !dry { down?.post(tap: .cghidEventTap) }
        nap(0.03)
        var waited = 0.03
        while waited < holdFor {                  // the system repeat rate, roughly
            let again = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: true)
            again?.flags = held
            again?.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            if !dry { again?.post(tap: .cghidEventTap) }
            nap(0.033)
            waited += 0.033
        }
        let up = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)
        up?.flags = held
        if !dry { up?.post(tap: .cghidEventTap) }
    } else {
        for n in 0..<max(1, repeats) {
            tapKey(code, flags: held)
            // Repeats of the same key are quick but not identical.
            if n + 1 < repeats { nap(Double.random(in: 0.06...0.16)) }
        }
    }
    releaseModifiers(held)
    beat()
}

/// Keys next to each other on QWERTY, for believable slips.
let neighbours: [Character: String] = [
    "a": "sqw", "b": "vgn", "c": "xvd", "d": "sfe", "e": "wrd", "f": "dgr", "g": "fhy",
    "h": "gju", "i": "uok", "j": "hkn", "k": "jli", "l": "ko", "m": "nj", "n": "bm",
    "o": "ipl", "p": "ol", "q": "wa", "r": "etf", "s": "adw", "t": "ryg", "u": "yih",
    "v": "cbf", "w": "qes", "x": "zcs", "y": "tuh", "z": "xa"
]

/// Dry mode keeps a model of what is on screen instead of posting events, so the
/// slip-and-correct logic can be proved without a window in the loop.
var dryBuffer: String?

/// Characters that need shift on a US layout, and the key they share.
let shiftedKeys: [Character: String] = [
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
    "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";",
    "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`"
]

var typeWithKeycodes = false

/// Pressing the actual key instead of injecting the character. Slower and layout-bound,
/// but terminals, games and some Electron apps ignore injected unicode entirely.
func keycodeFor(_ ch: Character) -> (CGKeyCode, Bool)? {
    if ch == "\n" || ch == "\r" { return (36, false) }
    if ch == "\t" { return (48, false) }
    if ch == " " { return (49, false) }
    if let base = shiftedKeys[ch], let code = keyCodes[base] { return (code, true) }
    if ch.isUppercase, let code = keyCodes[ch.lowercased()] { return (code, true) }
    if let code = keyCodes[String(ch)] { return (code, false) }
    return nil
}

func typeUnicode(_ s: String) {
    let hold = Double.random(in: 0.012...0.03)
    if typeWithKeycodes, !dry, let ch = s.first, s.count == 1, let (code, shift) = keycodeFor(ch) {
        let flags: CGEventFlags = shift ? .maskShift : []
        if shift {
            let m = CGEvent(keyboardEventSource: keySource, virtualKey: 56, keyDown: true)
            m?.type = .flagsChanged
            m?.flags = flags
            m?.post(tap: .cghidEventTap)
            nap(Double.random(in: 0.02...0.05))
        }
        tapKey(code, flags: flags)
        if shift {
            let m = CGEvent(keyboardEventSource: keySource, virtualKey: 56, keyDown: false)
            m?.type = .flagsChanged
            m?.flags = []
            m?.post(tap: .cghidEventTap)
            nap(Double.random(in: 0.015...0.04))
        }
        return
    }
    if dry { dryBuffer? += s; nap(hold); return }
    var chars = Array(s.utf16)
    let down = CGEvent(keyboardEventSource: keySource, virtualKey: 0, keyDown: true)
    let up = CGEvent(keyboardEventSource: keySource, virtualKey: 0, keyDown: false)
    down?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
    up?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
    down?.post(tap: .cghidEventTap)
    nap(hold)
    up?.post(tap: .cghidEventTap)
}

func backspace() {
    let hold = Double.random(in: 0.04...0.09)
    if dry {
        if !(dryBuffer?.isEmpty ?? true) { dryBuffer!.removeLast() }
        nap(hold)
        return
    }
    let down = CGEvent(keyboardEventSource: keySource, virtualKey: 51, keyDown: true)
    let up = CGEvent(keyboardEventSource: keySource, virtualKey: 51, keyDown: false)
    down?.post(tap: .cghidEventTap)
    nap(Double.random(in: 0.04...0.09))
    up?.post(tap: .cghidEventTap)
}

func gauss() -> Double {
    let u1 = max(Double.random(in: 0...1), 1e-9), u2 = Double.random(in: 0...1)
    return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
}

/// Inter-keystroke intervals are right-skewed, not uniform: mostly tight with a long
/// tail. Skilled means sit near 135-200ms in the 136M-keystroke corpus.
func iki(_ base: Double) -> Double { base * exp(gauss() * 0.34) }

let leftHand = Set("qwertasdfgzxcv12345`")
let rightHand = Set("yuiophjklnm67890-=[]\\;',./")

/// Alternating hands is the fastest digraph, same hand is slower, and repeating one
/// finger is slowest. This is most of what makes typing rhythm uneven.
func handFactor(_ prev: Character?, _ ch: Character) -> Double {
    guard let p = prev else { return 1 }
    let a = Character(p.lowercased()), b = Character(ch.lowercased())
    if a == b { return 1.3 }
    let la = leftHand.contains(a), ra = rightHand.contains(a)
    let lb = leftHand.contains(b), rb = rightHand.contains(b)
    if (la && rb) || (ra && lb) { return 0.84 }
    if (la && lb) || (ra && rb) { return 1.16 }
    return 1
}

func emit(_ ch: Character, _ prev: inout Character?, _ base: Double) {
    typeUnicode(String(ch))
    var delay = iki(base) * handFactor(prev, ch)
    prev = ch

    // Writing pauses cluster into three components: word retrieval near 330ms,
    // phrase boundaries near 735ms, and planning pauses of a couple of seconds.
    if ch == " " && Double.random(in: 0...1) < 0.07 { delay += 0.33 * exp(gauss() * 0.4) }
    if ".,;:!?".contains(ch) && Double.random(in: 0...1) < 0.45 { delay += 0.74 * exp(gauss() * 0.4) }
    if ch == "\n" { delay += Double.random(in: 0.2...0.6) }
    if Double.random(in: 0...1) < 0.004 { delay += 2.7 * exp(gauss() * 0.5) }
    nap(delay)
}

func neighbourKey(_ ch: Character) -> Character? {
    guard let near = neighbours[Character(ch.lowercased())], let pick = near.randomElement() else { return nil }
    return ch.isUppercase ? Character(String(pick).uppercased()) : pick
}

/// One slip, typed for real. Error mix follows typing corpora: substitution ~39%,
/// insertion ~33%, omission ~18%, transposition ~11%. Returns the index to resume at.
func slip(_ chars: [Character], _ i: Int, _ prev: inout Character?, _ base: Double, fix: Bool) -> Int {
    let ch = chars[i]
    let roll = Double.random(in: 0...1)
    var wrongOnScreen = 0        // characters to remove when correcting
    var resume = i + 1           // where to carry on if the slip is left alone
    var restart = i              // where to carry on after correcting

    if roll < 0.39, let wrong = neighbourKey(ch) {
        emit(wrong, &prev, base)
        wrongOnScreen = 1
    } else if roll < 0.72 {
        emit(ch, &prev, base)
        emit(neighbourKey(ch) ?? ch, &prev, base)
        wrongOnScreen = 1
        restart = i + 1
    } else if roll < 0.90 {
        // Omission: the key simply never lands.
    } else if i + 1 < chars.count && chars[i + 1] != "\n" {
        emit(chars[i + 1], &prev, base)
        emit(ch, &prev, base)
        wrongOnScreen = 2
        resume = i + 2
    } else {
        emit(ch, &prev, base)
        return i + 1
    }

    guard fix else { return resume }

    // Slips are usually caught a character or two late, not instantly.
    // The catch-up stays inside the word. Crossing a space lets the system's
    // autocorrect rewrite the word first, and then the backspace count is wrong.
    var trailing = 0
    let lookahead = Int.random(in: 0...2)
    while trailing < lookahead && resume + trailing < chars.count
        && neighbours[Character(chars[resume + trailing].lowercased())] != nil {
        emit(chars[resume + trailing], &prev, base)
        trailing += 1
    }
    nap(Double.random(in: 0.15...0.5))          // the double take
    for _ in 0..<(wrongOnScreen + trailing) {
        backspace()
        nap(base * Double.random(in: 0.5...1.1))
    }
    prev = nil
    return restart
}

func typeText(_ text: String, wpm: Double, accuracy: Accuracy) {
    if !dry {
        requireTrust("typing")
        enforceFocus("typing")
        // Secure input is what a password field turns on. Keys are swallowed with no
        // error, so half a sentence lands nowhere and the rest goes somewhere else.
        if IsSecureEventInputEnabled() {
            FileHandle.standardError.write(
                "human: secure input is on, keystrokes would be swallowed. Something has a password field focused.\n"
                    .data(using: .utf8)!)
            exit(7)
        }
    }
    // 12/wpm is seconds per character at the stated rate. Corrections and the pause
    // mixture add time on top, so the base is pre-shrunk to land on the asked-for
    // net speed, and shrunk further in the modes that stop to fix mistakes.
    let base = (12.0 / max(wpm, 5)) * (accuracy == .clean ? 0.65 : 0.49) * drift()
    let chars = Array(text)
    // Corrections run about 6% of keystrokes, and roughly one error in six survives.
    let errorRate = accuracy == .clean ? 0.0 : 0.055 * traits.errorScale
    var prev: Character? = nil
    var i = 0

    while i < chars.count {
        // Slips only on letters. Doubling a space trips the system's double-space to
        // period substitution, which rewrites the text behind the correction logic.
        if errorRate > 0 && neighbours[Character(chars[i].lowercased())] != nil
            && Double.random(in: 0...1) < errorRate {
            i = slip(chars, i, &prev, base, fix: accuracy == .human || Double.random(in: 0...1) > 0.17)
            continue
        }
        emit(chars[i], &prev, base)
        i += 1
    }
    beat()
}

// ============================================================================
// Idle presence
// ============================================================================

func settleTremor() {
    for _ in 0..<Int.random(in: 1...4) {
        let p = cursor()
        warp(CGPoint(x: p.x + CGFloat(Double.random(in: -2.5...2.5)),
                     y: p.y + CGFloat(Double.random(in: -2.5...2.5))))
        nap(Double.random(in: 0.05...0.35))
    }
}

func idleTarget(near p: CGPoint) -> CGPoint {
    // Half the time, drift toward something that is really there: a button, a field, a
    // line of text. Uniformly random points are the giveaway of a screensaver, and
    // hovering over real controls is one of the strongest human signals.
    if Double.random(in: 0...1) < 0.5, let root = axRoot(nil) {
        let worth = axTree(root, limit: 500).filter {
            clickableRoles.contains($0.role) && $0.rect.width > 10 && $0.rect.height > 10
                && $0.rect.width < screen.width * 0.85
        }
        if let pick = worth.randomElement() {
            return onScreen(CGPoint(
                x: pick.rect.midX + CGFloat(Double.random(in: -0.35...0.35)) * pick.rect.width,
                y: pick.rect.midY + CGFloat(Double.random(in: -0.35...0.35)) * pick.rect.height))
        }
    }
    let roll = Double.random(in: 0...1)
    // Mostly short local adjustments, occasionally a real trip across the screen.
    let reach: Double = roll < 0.55 ? Double.random(in: 15...120)
                      : roll < 0.88 ? Double.random(in: 120...420)
                      : Double.random(in: 420...1200)
    let ang = Double.random(in: 0...(2 * Double.pi))
    let margin: CGFloat = 70
    return CGPoint(x: min(max(p.x + CGFloat(reach * cos(ang)), screen.minX + margin), screen.maxX - margin),
                   y: min(max(p.y + CGFloat(reach * sin(ang)), screen.minY + margin), screen.maxY - margin))
}

func idlePause() -> Double {
    let roll = Double.random(in: 0...1)
    if roll < 0.50 { return Double.random(in: 0.4...2.5) }   // reading a line
    if roll < 0.85 { return Double.random(in: 2.5...9) }     // reading a page
    return Double.random(in: 9...40)                          // away from the desk
}

func runIdle(minutes: Double, verbose: Bool, yield: Bool) {
    let deadline = minutes > 0 ? Date().addingTimeInterval(minutes * 60) : Date.distantFuture
    func log(_ s: String) {
        guard verbose else { return }
        FileHandle.standardError.write("human: \(s)\n".data(using: .utf8)!)
    }
    func napUntil(_ seconds: Double) {
        var left = seconds
        while left > 0 && Date() < deadline { let s = min(left, 0.25); nap(s); left -= s }
    }

    var lastLeftAt = cursor()
    var firstPass = true
    log("idling on \(Int(screen.width))x\(Int(screen.height))")

    while Date() < deadline {
        let now = cursor()
        // Something else moved the pointer while we rested: that is the human. Yield
        // rather than fight them for the cursor.
        if yield && !firstPass && dist(now, lastLeftAt) > 8 {
            log(String(format: "yielding, pointer drifted %.0fpx", dist(now, lastLeftAt)))
            napUntil(Double.random(in: 25...70))
            lastLeftAt = cursor()
            continue
        }
        firstPass = false

        // Attention comes in episodes, not a steady drip. A pointer that glides
        // somewhere every few seconds reads as a screensaver however good each single
        // movement is: what gives a person away is the clumping, and the long stillness.
        let roll = Double.random(in: 0...1)
        if roll < 0.12 {
            let away = Double.random(in: 40...240)
            log(String(format: "away from the desk, %.0fs", away))
            napUntil(away)
            lastLeftAt = cursor()
            continue
        }

        let (moves, gapLow, gapHigh, label): (Int, Double, Double, String)
        if roll < 0.5 {
            (moves, gapLow, gapHigh, label) = (Int.random(in: 2...6), 0.6, 3.0, "reading")
        } else if roll < 0.78 {
            (moves, gapLow, gapHigh, label) = (Int.random(in: 1...3), 0.4, 1.5, "scanning")
        } else {
            (moves, gapLow, gapHigh, label) = (Int.random(in: 3...8), 0.15, 0.6, "busy")
        }

        var travelled = 0.0
        for i in 0..<moves {
            if Date() >= deadline { break }
            let from = cursor()
            // Reading stays put and fidgets; scanning and busy work move between things.
            let target = label == "reading" && i > 0
                ? onScreen(CGPoint(x: from.x + CGFloat(Double.random(in: -60...60)),
                                   y: from.y + CGFloat(Double.random(in: -40...40))))
                : idleTarget(near: from)
            moveTo(target)
            travelled += dist(from, target)
            if Double.random(in: 0...1) < 0.3 { settleTremor() }
            napUntil(Double.random(in: gapLow...gapHigh))
        }

        lastLeftAt = cursor()
        let rest = label == "busy" ? Double.random(in: 5...20) : Double.random(in: 3...16)
        log(String(format: "%@: %d moves, %.0fpx, then %.0fs still", label, moves, travelled, rest))
        napUntil(rest)
    }
    log("done")
}

// ============================================================================
// CLI
// ============================================================================

var argv = Array(CommandLine.arguments.dropFirst())

func takeFlag(_ name: String) -> Bool {
    guard let i = argv.firstIndex(of: name) else { return false }
    argv.remove(at: i)
    return true
}

func takeValue(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    let v = argv[i + 1]
    argv.removeSubrange(i...(i + 1))
    return v
}

func modifierFlags() -> CGEventFlags {
    var f = CGEventFlags()
    if takeFlag("--cmd") { f.insert(.maskCommand) }
    if takeFlag("--shift") { f.insert(.maskShift) }
    if takeFlag("--opt") || takeFlag("--alt") { f.insert(.maskAlternate) }
    if takeFlag("--ctrl") { f.insert(.maskControl) }
    if takeFlag("--fn") { f.insert(.maskSecondaryFn) }
    return f
}

func point(_ a: String?, _ b: String?) -> CGPoint? {
    guard let a = a, let b = b, let x = Double(a), let y = Double(b) else { return nil }
    return CGPoint(x: x, y: y)
}

let usage = """
human - drive macOS the way a person does (curved pointer paths, real dwell, varied timing)

  human check                       permissions, screen size, cursor position
  human where                       print cursor as x,y
  human front                       name of the frontmost app
  human focus <AppName>             bring an app forward and wait until it really is
  human move <x> <y>                glide the pointer there
  human click [x y] [--right] [--double]
  human drag <x1> <y1> <x2> <y2> [--precise]
  human scroll <amount> [x y] [--horizontal] negative scrolls down; x y puts the
                                    pointer over the thing to scroll first
  human type "text" [--wpm 70] [--accuracy clean|human|raw]
                                    human (default) slips and fixes them, final text exact
                                    raw leaves about 1 in 6 slips uncorrected
                                    clean never mistypes
  human key <name> [--cmd --shift --opt --ctrl]
  human open <AppName>              bring an app to the front, then settle
  human wait <seconds>              waits a human-ish spread around that value
  human idle [--minutes N] [--no-yield] [--verbose]
  human run <file|-> [--verbose] [--dry]   one command per line, # comments allowed
  human selftest                    prove the pointer, typing, guard and sight still work
  human stop / human go             set or clear the abort flag
  human unstick                     release any modifier or button left held down

Add --require <AppName> to any action and it refuses to fire unless that app is in
front, so a missing window can never send keystrokes into the wrong place.

Every action lands with its own small delays, so sequences do not tick like a clock.
"""

guard let cmd = argv.first else { print(usage); exit(0) }
argv.removeFirst()

func execute(_ cmd: String, _ rest: [String]) {
    let saved = argv
    argv = rest
    defer { argv = saved }
    if let want = takeValue("--require") { requiredApp = want }
    if takeFlag("--precise") { precise = true }
    if takeFlag("--ocr") { useOCR = true }
    if takeFlag("--fast") { ocrFast = true }
    if takeFlag("--dry") { dry = true }
    if let who = takeValue("--persona") { traits = personaTraits(who) }

    switch cmd {
    case "check":
        let p = cursor()
        print("accessibility:    \(trusted ? "granted" : "NOT granted - clicks, keys and scroll will refuse")")
        print("screen recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted - no pixel eyes, no OCR")")
        let listening = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        print("input monitoring: \(listening ? "granted" : "not granted - only needed to listen, not to send")")
        print("secure input:     \(IsSecureEventInputEnabled() ? "ON - something has a password field focused, keystrokes are blocked" : "off")")
        print("screen: \(Int(screen.width))x\(Int(screen.height))")
        print("cursor: \(Int(p.x)),\(Int(p.y))")

    case "where":
        let p = cursor()
        print("\(Int(p.x)),\(Int(p.y))")

    case "front":
        print(frontmostApp())

    case "see":
        let app = takeValue("--app")
        let role = takeValue("--role")
        let limit = Int(takeValue("--limit") ?? "") ?? 60
        let everything = takeFlag("--all")
        guard let root = axRoot(app) else {
            FileHandle.standardError.write("human: no app named '\(app ?? frontmostApp())'\n".data(using: .utf8)!)
            exit(2)
        }
        var shown = 0
        for s in axTree(root) {
            if let want = role, s.role.lowercased() != want.lowercased() { continue }
            if role == nil && !everything && !clickableRoles.contains(s.role) { continue }
            if !everything && s.label.isEmpty && s.subrole.isEmpty { continue }
            print("\(Int(s.rect.midX)),\(Int(s.rect.midY))\t\(s.role)\t\(Int(s.rect.width))x\(Int(s.rect.height))\t\(s.name.prefix(60))")
            shown += 1
            if shown >= limit { break }
        }

    case "pane":
        let sub = argv.first ?? "list"
        if !argv.isEmpty { argv.removeFirst() }
        switch sub {
        case "list":
            print(run(requireWezterm(), ["cli", "list"]).out, terminator: "")
        case "read":
            guard let id = argv.first else {
                FileHandle.standardError.write("human: pane read needs a pane id\n".data(using: .utf8)!); exit(2)
            }
            print(paneText(id), terminator: "")
        case "send":
            guard let id = argv.first else {
                FileHandle.standardError.write("human: pane send needs a pane id\n".data(using: .utf8)!); exit(2)
            }
            argv.removeFirst()
            let enter = takeFlag("--enter")
            var text = argv.joined(separator: " ").replacingOccurrences(of: "\\n", with: "\n")
            if enter { text += "\r" }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: requireWezterm())
            p.arguments = ["cli", "send-text", "--pane-id", id, "--no-paste"]
            let input = Pipe()
            p.standardInput = input
            try? p.run()
            input.fileHandleForWriting.write(text.data(using: .utf8)!)
            input.fileHandleForWriting.closeFile()
            p.waitUntilExit()
        case "waitfor":
            guard argv.count >= 2 else {
                FileHandle.standardError.write("human: pane waitfor needs <id> <pattern>\n".data(using: .utf8)!); exit(2)
            }
            let id = argv.removeFirst()
            let timeout = Double(takeValue("--timeout") ?? "") ?? 300
            let gone = takeFlag("--gone")
            let pattern = argv.joined(separator: " ")
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if paneMatches(paneText(id), pattern) != gone { exit(0) }
                nap(1.0)
            }
            FileHandle.standardError.write("human: pane \(id) never \(gone ? "cleared" : "showed") '\(pattern)'\n".data(using: .utf8)!)
            exit(6)
        default:
            FileHandle.standardError.write("human: pane list|read|send|waitfor\n".data(using: .utf8)!)
            exit(2)
        }

    case "read":
        var region = screen
        if let spec = takeValue("--region") {
            let n = spec.split(separator: ",").compactMap { Double($0) }
            if n.count == 4 { region = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
        }
        let lines = ocrRead(region, fast: ocrFast)
        if lines.isEmpty {
            FileHandle.standardError.write("human: read nothing. is Screen Recording granted?\n".data(using: .utf8)!)
            exit(1)
        }
        for l in lines.sorted(by: { $0.rect.minY == $1.rect.minY ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY }) {
            print("\(Int(l.centre.x)),\(Int(l.centre.y))\t\(l.label)")
        }

    case "find":
        let app = takeValue("--app")
        let role = takeValue("--role")
        let all = takeFlag("--all")
        let withRect = takeFlag("--rect")
        let hits = find(argv.joined(separator: " "), app: app, role: role, all: all)
        guard !hits.isEmpty else { exit(1) }
        for h in hits {
            if withRect {
                print("\(Int(h.rect.minX)),\(Int(h.rect.minY)),\(Int(h.rect.width)),\(Int(h.rect.height))\t\(h.role)\t\(h.name.prefix(60))")
            } else if all {
                print("\(Int(h.centre.x)),\(Int(h.centre.y))\t\(h.role)\t\(h.name.prefix(60))")
            } else {
                print("\(Int(h.centre.x)) \(Int(h.centre.y))")
            }
        }

    case "waitfor":
        let app = takeValue("--app")
        let role = takeValue("--role")
        let timeout = Double(takeValue("--timeout") ?? "") ?? 20
        let untilGone = takeFlag("--gone")
        let needle = argv.joined(separator: " ")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let there = !find(needle, app: app, role: role, all: false).isEmpty
            if there != untilGone {
                nap(Double.random(in: 0.2...0.5))     // a person does not react instantly
                exit(0)
            }
            nap(0.25)
        }
        FileHandle.standardError.write(
            "human: waited \(Int(timeout))s, '\(needle)' never \(untilGone ? "went away" : "appeared")\n"
                .data(using: .utf8)!)
        exit(6)

    case "unstick":
        // An aborted command can leave a modifier or a button down, and everything
        // afterwards behaves strangely for reasons that are invisible.
        var cleared: [String] = []
        for (flag, code) in modifierKeys where CGEventSource.flagsState(.combinedSessionState).contains(flag) {
            let e = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)
            e?.type = .flagsChanged
            e?.flags = []
            e?.post(tap: .cghidEventTap)
            cleared.append("modifier \(code)")
            nap(0.03)
        }
        for button in [CGMouseButton.left, .right, .center]
        where CGEventSource.buttonState(.combinedSessionState, button: button) {
            let type: CGEventType = button == .right ? .rightMouseUp
                : button == .center ? .otherMouseUp : .leftMouseUp
            postMouse(type, cursor(), button)
            cleared.append("button \(button.rawValue)")
        }
        print(cleared.isEmpty ? "nothing was stuck" : "released " + cleared.joined(separator: ", "))

    case "stop":
        FileManager.default.createFile(atPath: stopFile, contents: nil)
        print("stop flag set, running actions will abort (human go to clear)")

    case "go":
        try? FileManager.default.removeItem(atPath: stopFile)
        print("stop flag cleared")

    case "focus":
        let name = argv.joined(separator: " ")
        guard !name.isEmpty else {
            FileHandle.standardError.write("human: focus needs an app name\n".data(using: .utf8)!); exit(2)
        }
        if dry { print("would focus \(name)"); break }
        if !focusApp(name) {
            FileHandle.standardError.write(
                "human: could not bring '\(name)' to the front, '\(frontmostApp())' still is\n".data(using: .utf8)!)
            exit(4)
        }

    case "move":
        guard let t = point(argv.first, argv.dropFirst().first) else {
            FileHandle.standardError.write("human: move needs <x> <y>\n".data(using: .utf8)!); exit(2)
        }
        moveTo(t)

    case "click":
        let right = takeFlag("--right")
        let middle = takeFlag("--middle")
        let double = takeFlag("--double")
        let triple = takeFlag("--triple")
        let holdFor = Double(takeValue("--hold") ?? "") ?? 0
        let clickMods = modifierFlags()
        let app = takeValue("--app")
        let role = takeValue("--role")
        var t = point(argv.first, argv.dropFirst().first)
        if t == nil && !argv.isEmpty {
            // Not coordinates, so treat it as a name and go find the thing.
            let needle = argv.joined(separator: " ")
            guard let hit = find(needle, app: app, role: role, all: false).first else {
                FileHandle.standardError.write("human: could not see '\(needle)'\n".data(using: .utf8)!)
                exit(1)
            }
            t = hit.centre
            if hit.rect.width < 12 || hit.rect.height < 12 { precise = true }
        }
        click(at: t, button: right ? .right : middle ? .center : .left,
              times: triple ? 3 : double ? 2 : 1, modifiers: clickMods, holdFor: holdFor)

    case "drag":
        guard argv.count >= 4, let a = point(argv[0], argv[1]), let b = point(argv[2], argv[3]) else {
            FileHandle.standardError.write("human: drag needs <x1> <y1> <x2> <y2>\n".data(using: .utf8)!); exit(2)
        }
        drag(from: a, to: b)

    case "scroll":
        let horizontal = takeFlag("--horizontal")
        guard let n = Int(argv.first ?? "") else {
            FileHandle.standardError.write("human: scroll needs an amount\n".data(using: .utf8)!); exit(2)
        }
        scroll(n, horizontal: horizontal, over: point(argv.dropFirst().first, argv.dropFirst(2).first))

    case "type":
        let wpm = Double(takeValue("--wpm") ?? "") ?? traits.wpm
        let accuracy: Accuracy
        switch takeValue("--accuracy") ?? "human" {
        case "clean": accuracy = .clean
        case "raw": accuracy = .raw
        default: accuracy = .human
        }
        if takeFlag("--keys") { typeWithKeycodes = true }
        let repeatArg = takeValue("--repeat")
        let text = argv.joined(separator: " ").replacingOccurrences(of: "\\n", with: "\n")
        guard !text.isEmpty else { exit(0) }
        if let repeatArg = repeatArg {
            dry = true
            var exact = 0
            var total = 0.0
            let n = max(1, Int(repeatArg) ?? 1)
            for _ in 0..<n {
                dryBuffer = ""
                dryElapsed = 0
                typeText(text, wpm: wpm, accuracy: accuracy)
                total += dryElapsed
                if dryBuffer == text { exact += 1 } else if n == 1 { print(dryBuffer!) }
            }
            let netWpm = (Double(text.count) / 5) / (total / Double(n) / 60)
            print(String(format: "exact %d/%d, %.1f wpm net (asked %.0f)", exact, n, netWpm, wpm))
        } else {
            if dry { dryBuffer = "" }
            typeText(text, wpm: wpm, accuracy: accuracy)
            dryBuffer = nil
        }

    case "key":
        guard let name = argv.first else {
            FileHandle.standardError.write("human: key needs a name\n".data(using: .utf8)!); exit(2)
        }
        argv.removeFirst()
        let repeats = Int(takeValue("--repeat") ?? "") ?? 1
        let holdFor = Double(takeValue("--hold") ?? "") ?? 0
        pressKey(name, extra: modifierFlags(), repeats: repeats, holdFor: holdFor)

    case "open":
        let app = argv.joined(separator: " ")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", app]
        try? task.run()
        task.waitUntilExit()
        nap(Double.random(in: 0.6...1.6))         // wait for the window like a person would

    case "wait":
        let s = Double(argv.first ?? "") ?? 1
        nap(s * Double.random(in: 0.85...1.2))

    case "idle":
        let minutes = Double(takeValue("--minutes") ?? "") ?? 0
        runIdle(minutes: minutes, verbose: takeFlag("--verbose"), yield: !takeFlag("--no-yield"))

    case "selftest":
        let home = cursor()
        var failed = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "pass" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
            if !ok { failed += 1 }
        }
        check("accessibility granted", trusted)
        check("no stop flag set", !FileManager.default.fileExists(atPath: stopFile))

        var worst = 0.0
        for t in [CGPoint(x: 260, y: 220), CGPoint(x: screen.maxX - 180, y: screen.maxY - 160),
                  CGPoint(x: screen.midX, y: screen.midY)] {
            moveTo(t)
            worst = max(worst, dist(cursor(), t))
        }
        // It lands inside the target, not on a chosen pixel: the last couple of pixels
        // are left to the settle, because a hand does not spend a submovement on them.
        check("pointer lands inside the target", worst < 5, String(format: "worst miss %.1fpx", worst))

        let sample = "the quarterly numbers look right to me"
        var exact = 0
        let wasDry = dry
        dry = true
        for _ in 0..<200 {
            dryBuffer = ""
            typeText(sample, wpm: 70, accuracy: .human)
            if dryBuffer == sample { exact += 1 }
        }
        dryBuffer = nil
        dry = wasDry
        check("typing corrects every slip", exact == 200, "\(exact)/200 exact")

        let front = frontmostApp()
        check("can name the frontmost app", !front.isEmpty, front)
        let tree = axRoot(nil).map { axTree($0).count } ?? 0
        check("can see the interface", tree > 0, "\(tree) elements in \(front)")

        moveTo(home)
        print(failed == 0 ? "all good" : "\(failed) failed")
        exit(failed == 0 ? 0 : 1)

    case "help", "--help", "-h":
        print(usage)

    default:
        FileHandle.standardError.write("human: unknown command '\(cmd)'\n\n\(usage)\n".data(using: .utf8)!)
        exit(2)
    }
}

if cmd == "run" {
    let verbose = takeFlag("--verbose")
    if takeFlag("--dry") { dry = true }
    let path = argv.first ?? "-"
    let body: String
    if path == "-" {
        body = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    } else {
        body = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        // Quoted text stays one argument so `type "hello there"` works.
        var parts: [String] = []
        var current = ""
        var quoted = false
        for c in line {
            if c == "\"" { quoted.toggle(); continue }
            if c == " " && !quoted { if !current.isEmpty { parts.append(current); current = "" }; continue }
            current.append(c)
        }
        if !current.isEmpty { parts.append(current) }
        guard let head = parts.first else { continue }
        if verbose { FileHandle.standardError.write("human: \(line)\n".data(using: .utf8)!) }
        execute(head, Array(parts.dropFirst()))
        nap(Double.random(in: 0.12...0.45))       // gap between deliberate actions
    }
    if dry {
        print(String(format: "rehearsal only, nothing was touched. would take about %.0fs", dryElapsed))
    }
} else {
    execute(cmd, argv)
}
