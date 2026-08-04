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

/// The same person is not identical on two different days: sleep, coffee, mood. Narrow
/// enough to stay recognisably them, wide enough that months of runs are not one fixed
/// signature sitting there to be measured.
func dayDrift(_ base: Traits, seed: String = "", day: Int = Int(Date().timeIntervalSince1970 / 86_400)) -> Traits {
    var h = UInt64(bitPattern: Int64(day))
    for b in seed.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
    func spread(_ width: Double) -> Double {
        h ^= h >> 30; h = h &* 0xbf58_476d_1ce4_e5b9; h ^= h >> 27
        return 1 + width * (Double(h % 10_000) / 10_000 * 2 - 1)
    }
    var t = base
    t.pace *= spread(0.08)
    t.tremor *= spread(0.12)
    t.errorScale *= spread(0.15)
    t.wpm *= spread(0.06)
    return t
}

var traits = dayDrift(Traits())

func personaTraits(_ name: String) -> Traits {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
    func next(_ lo: Double, _ hi: Double) -> Double {
        h ^= h >> 33; h = h &* 0xff51_afd7_ed55_8ccd; h ^= h >> 29
        return lo + (hi - lo) * Double(h % 10_000) / 10_000
    }
    return dayDrift(Traits(pace: next(0.82, 1.22), bowBias: next(0.15, 0.85),
                           tremor: next(0.6, 1.5), errorScale: next(0.5, 1.7),
                           wpm: next(52, 88)), seed: name)
}

let startedAt = Date()

/// Every action, appended, so an unattended run can be read afterwards. Without this a
/// long run is a black box: you know what you asked for and not what happened.
let auditPath = NSHomeDirectory() + "/Library/Logs/human-input.log"

func audit(_ line: String) {
    guard !dry else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let entry = "\(stamp) \(line)\n"
    let url = URL(fileURLWithPath: auditPath)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = FileHandle(forWritingAtPath: auditPath) {
        handle.seekToEndOfFile()
        handle.write(entry.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? entry.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// A session has a shape: a slow start while you settle in, a long steady middle, then
/// a gradual slide as you tire. Returned as a time multiplier, so above 1 is slower.
/// Split from the session it usually reads so the curve itself can be checked.
func drift(_ worked: Double) -> Double {
    if worked < 8 { return 1.10 - 0.05 * (worked / 8) }        // still warming up
    if worked < 150 { return 1.0 }
    return min(1.0 + (worked - 150) * 0.0006, 1.18)            // tiring
}

func drift() -> Double { drift(Double(session.actions)) }

/// Work done, not just time passed. Each command is its own process, so the count is
/// kept on disk and reset when there has been a real gap: an hour of steady clicking
/// tires a person, an hour of sitting there does not.
struct Session {
    var actions: Int
    var lastAt: Date
    var lastVerb: String?
}

/// Rest recovers, and not in one step. A couple of minutes away is still the same stint,
/// twenty minutes is half a recovery, a night is a fresh start. A threshold that wipes
/// the count makes somebody who stretched their legs identical to somebody who has only
/// just sat down, and puts a cliff in the one curve that should not have one.
func recovered(_ actions: Int, resting seconds: Double) -> Int {
    guard seconds > 120 else { return actions }
    return Int((Double(actions) * pow(0.5, (seconds - 120) / 1200)).rounded())
}

func loadSession() -> Session {
    let path = NSHomeDirectory() + "/Library/Caches/human-input/session.json"
    guard let d = FileManager.default.contents(atPath: path),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let n = j["actions"] as? Double, let at = j["lastAt"] as? Double else {
        return Session(actions: 0, lastAt: Date(), lastVerb: nil)
    }
    let last = Date(timeIntervalSince1970: at)
    let rested = Date().timeIntervalSince(last)
    // After a real break you are not mid-flow with whatever you were last doing, so the
    // verb goes even though the tiredness only fades.
    return Session(actions: recovered(Int(n), resting: rested), lastAt: last,
                   lastVerb: rested < 600 ? j["lastVerb"] as? String : nil)
}

var session = loadSession()

/// What the caller already spent between the last command and this one. Each command is
/// its own process, so some of the gap a person would have taken may have passed on its
/// own — and it may not have passed at all.
var gapBefore = Date().timeIntervalSince(session.lastAt)

/// A rehearsal, a permission check or the abort flag is not somebody at the machine, and
/// recording one as work would age the session that has not started yet.
var touched = false

func saveSession() {
    guard touched else { return }
    let dir = NSHomeDirectory() + "/Library/Caches/human-input"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var blob: [String: Any] = ["actions": Double(session.actions),
                               "lastAt": Date().timeIntervalSince1970]
    if let verb = session.lastVerb { blob["lastVerb"] = verb }
    if let raw = try? JSONSerialization.data(withJSONObject: blob) {
        try? raw.write(to: URL(fileURLWithPath: dir + "/session.json"))
    }
}

/// Tiredness costs accuracy as well as speed, and it comes from doing things.
func fatigueErrorScale(_ worked: Double) -> Double {
    worked < 120 ? 1.0 : min(1 + (worked - 120) * 0.0015, 1.45)
}

func fatigueErrorScale() -> Double { fatigueErrorScale(Double(session.actions)) }

var device = "mouse"
var familiarHaste = 1.0

/// Things done before, how often and how long ago. The same curve governs a button you
/// keep clicking and a string you keep typing, because underneath it is the same motor
/// learning — so it is the same store, twice.
struct Practice {
    var visits: Double
    var lastAt: Double
}

/// Practice fades. A button hit fifty times last month is not the reflex it was, and a
/// speed that only ever ratchets up is a counter rather than a skill.
func practiced(_ p: Practice) -> Double {
    let days = max(0, (Date().timeIntervalSince1970 - p.lastAt) / 86_400)
    return p.visits * pow(0.5, days / 14)
}

/// Skill is a power law: the first few repetitions buy most of the speed and then it
/// flattens off. A straight line that ratchets into a ceiling is a counter wearing a
/// curve's clothes, and the kink where it clamps is visible in the timings.
func skillGain(_ seen: Double, ceiling: Double, scale: Double = 6) -> Double {
    1 + ceiling * (1 - exp(-max(0, seen) / scale))
}

struct PracticeStore {
    let file: String
    let cap: Int
    var entries: [String: Practice]
    var dirty = false

    init(_ file: String, cap: Int = 3000) {
        self.file = file
        self.cap = cap
        let path = NSHomeDirectory() + "/Library/Caches/human-input/" + file
        let raw = FileManager.default.contents(atPath: path)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        entries = PracticeStore.parse(raw ?? [:])
    }

    /// Both shapes this file has ever had, because a cache that fails to load is a hand
    /// that forgot everything it knew.
    static func parse(_ j: [String: Any]) -> [String: Practice] {
        let now = Date().timeIntervalSince1970
        var out: [String: Practice] = [:]
        // Through NSNumber, because a whole number and a fractional one arrive as
        // different Swift types and a cast straight to Double drops the whole ones.
        for (key, value) in j {
            if let pair = value as? [NSNumber], pair.count == 2 {
                out[key] = Practice(visits: pair[0].doubleValue, lastAt: pair[1].doubleValue)
            } else if let bare = value as? NSNumber {
                out[key] = Practice(visits: bare.doubleValue, lastAt: now)   // the older dateless format
            }
        }
        return out
    }

    /// Repetitions to date, decayed to now.
    func seen(_ key: String) -> Double { entries[key].map(practiced) ?? 0 }

    /// One more repetition, rebased to now so the decay always runs from the last time it
    /// was really done. A rehearsal teaches it nothing.
    mutating func record(_ key: String, after seen: Double) {
        guard !dry else { return }
        entries[key] = Practice(visits: seen + 1, lastAt: Date().timeIntervalSince1970)
        dirty = true
    }

    mutating func save() {
        guard dirty else { return }
        // Bounded, because this is written on every run and nothing ever removes an
        // entry. Dropping by decayed value keeps what is still practised rather than what
        // was once busy: a target from six months ago is not worth a slot.
        if entries.count > cap {
            let keep = entries.sorted { practiced($0.value) > practiced($1.value) }.prefix(cap * 2 / 3)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        let dir = NSHomeDirectory() + "/Library/Caches/human-input"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let blob = entries.mapValues { [$0.visits, $0.lastAt] }
        if let raw = try? JSONSerialization.data(withJSONObject: blob) {
            try? raw.write(to: URL(fileURLWithPath: dir + "/" + file))
        }
    }
}

var pointerPractice = PracticeStore("familiarity.json")
var typingPractice = PracticeStore("typing.json", cap: 600)

func savePractice() {
    pointerPractice.save()
    typingPractice.save()
}

func familiarKey(_ p: CGPoint) -> String { "\(Int(p.x) / 20),\(Int(p.y) / 20)" }

/// A string typed before, recognised without keeping it. The hash is truncated to twelve
/// bits, so the store holds a bucket one string in four thousand lands in rather than the
/// text: it cannot be searched for a password somebody already suspects, which is the
/// same reason the audit log records that typing happened and never what was typed. The
/// cost is that two unrelated strings occasionally read as practice for each other — a
/// harmless way to be wrong, and nothing like keeping the words.
func typingKey(_ text: String) -> String? {
    // Chunking is a sequence the fingers know as one motion. Two characters is not a
    // sequence, and single keys are already covered by the digraph timings.
    guard text.count >= 3 else { return nil }
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
    return String(h & 0xfff, radix: 16)
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
var terminateRequested: sig_atomic_t = 0

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
    if terminateRequested != 0 {
        releaseEverythingHeld()
        savePractice()
        exit(130)
    }
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

/// What the hands and eyes are busy with. Changing channel costs real time: the hand
/// leaves the mouse for the keyboard, the eyes leave the pointer for a line of text.
func channel(_ verb: String) -> String {
    switch verb {
    case "move", "click", "drag", "scroll", "gesture": return "pointer"
    case "type", "key", "text": return "keyboard"
    case "see", "find", "read", "check", "state", "changed", "waitfor",
         "where", "front", "dialog", "pixel", "find-image", "snip": return "look"
    case "focus", "open", "window", "pane": return "app"
    default: return "other"
    }
}

/// Commands that are not a person doing anything: diagnostics, the abort flag, the
/// script runner itself. No pause belongs in front of them.
let offstage: Set<String> = ["stop", "go", "unstick", "check", "selftest", "worklog",
                             "record", "idle", "plan", "run", "help", "--help", "-h"]

/// The gap between two deliberate actions, shaped by what just happened. Every command
/// is its own process, so without this the seams between them run on the caller's clock:
/// motion sampled from a real hand, stitched together at machine cadence. Whatever the
/// caller already spent thinking counts towards it — a person who just paused for nine
/// seconds does not then pause again.
func transitionPause(from last: String?, to next: String, since elapsed: Double) {
    guard !offstage.contains(next), channel(next) != "look" else { return }
    let to = channel(next)
    let from = last.map(channel)
    var want: Double
    if from == nil { want = Double.random(in: 0.4...1.2) }            // settling in
    else if from == "look" { want = Double.random(in: 0.5...1.6) }    // taking it in
    else if from == "app" { want = Double.random(in: 0.6...1.8) }     // waiting on the window
    else if from != to { want = Double.random(in: 0.35...0.9) }       // hand changes device
    else if last == next { want = Double.random(in: 0.10...0.35) }    // in flow
    else { want = Double.random(in: 0.18...0.5) }
    // Attention is not a metronome. Every so often something needs thinking about, and
    // that long tail is most of what separates a person's cadence from a schedule.
    if Double.random(in: 0...1) < 0.07 { want += Double.random(in: 1.5...4.0) }
    let owed = max(0, want * drift() - elapsed)
    // Reading is something you do during work, not only in the idle command. Having just
    // looked at the screen, the hand drifts over what is being read instead of resting on
    // the pixel it last clicked — but only half the time, because a hand often does just
    // sit there, and never mid-drag.
    if from == "look", owed > 0.5, buttonHeld == nil, Double.random(in: 0...1) < 0.5 {
        readingDrift(owed)
    } else {
        nap(owed)
    }
}

/// Small and local on purpose. This runs during real work, where a pointer wandering
/// across an app is a pointer opening hover menus nobody asked for; the drift of reading
/// a line is a few centimetres of desk, not a trip across the screen. Consumes exactly
/// the time it was given, so a rehearsal still estimates the run correctly.
func readingDrift(_ seconds: Double) {
    let began = Date(), start = dryElapsed
    func spent() -> Double { dry ? dryElapsed - start : Date().timeIntervalSince(began) }
    // The margin covers the next hop; the pause after it is clamped to what is left, so
    // the budget is met exactly rather than approximately.
    while seconds - spent() > 0.35 {
        let p = cursor()
        submove(from: p, to: onScreen(CGPoint(x: p.x + CGFloat(Double.random(in: -70...70)),
                                              y: p.y + CGFloat(Double.random(in: -28...28)))),
                width: 60, primary: false)
        nap(min(Double.random(in: 0.12...0.45), max(0, seconds - spent())))
    }
    nap(max(0, seconds - spent()))
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

/// App names are not always what they look like: WhatsApp's begins with an invisible
/// left-to-right mark, so an exact comparison silently fails to find a running app.
/// Bundle identifiers are accepted too, since they have no such surprises.
func appMatches(_ app: NSRunningApplication, _ wanted: String) -> Bool {
    func clean(_ s: String) -> String {
        s.unicodeScalars.filter { !(0x200B...0x200F).contains($0.value) && $0.value != 0xFEFF }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
    let want = clean(wanted)
    if let name = app.localizedName, clean(name) == want { return true }
    if let bundle = app.bundleIdentifier, bundle.lowercased() == want { return true }
    if let name = app.localizedName, clean(name).contains(want), !want.isEmpty { return true }
    return false
}

func runningApp(named: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { appMatches($0, named) }
}

func focusApp(_ name: String, timeout: Double = 12) -> Bool {
    let wasRunning = runningApp(named: name) != nil
    if let app = runningApp(named: name) {
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
    // An app that is already running comes forward at once or not at all, so spending
    // the whole timeout before trying the other way just makes every failure slow.
    if waitForFront(name, timeout: wasRunning ? 1.5 : timeout) { return true }

    // WhatsApp ignores NSRunningApplication.activate on macOS 26 while still honouring
    // an Apple Event. Nothing is lost by asking a second way before giving up.
    if let bundle = runningApp(named: name)?.bundleIdentifier {
        _ = run("/usr/bin/osascript", ["-e", "tell application id \"\(bundle)\" to activate"])
        if waitForFront(name, timeout: wasRunning ? max(timeout - 3, 4) : 4) { return true }
    }
    return NSWorkspace.shared.frontmostApplication.map { appMatches($0, name) } ?? false
}

/// NSWorkspace only learns about the switch through notifications, so the run loop has
/// to be pumped while waiting or frontmostApplication never changes in this process.
func waitForFront(_ name: String, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        if let front = NSWorkspace.shared.frontmostApplication, appMatches(front, name) {
            nap(Double.random(in: 0.25...0.6))
            return true
        }
    }
    return false
}

var requiredApp: String?

func enforceFocus(_ what: String) {
    guard let want = requiredApp, !dry else { return }
    let have = frontmostApp()
    if let front = NSWorkspace.shared.frontmostApplication, appMatches(front, want) { return }
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
    /// Kept so a candidate can be checked for identity against a hit test. Elements read
    /// from pixels have none.
    var el: AXUIElement? = nil
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

/// The window the user is actually looking at. An app publishes every window it owns, so
/// without this a background window's contents read exactly like the front one's.
func focusedWindow(_ root: AXUIElement) -> AXUIElement? {
    guard let v = axValue(root, kAXFocusedWindowAttribute as String),
          CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(v, to: AXUIElement.self)
}

/// `onlyWindow` keeps the walk out of the app's other windows. Chrome with two windows
/// open handed out tab coordinates from the background one, and clicking them landed in
/// whichever window was actually in front — a different tab entirely. Menus and the menu
/// bar are not AXWindow, so they still come through.
func axTree(_ root: AXUIElement, limit: Int = 4000, maxDepth: Int = 24,
            onlyWindow: AXUIElement? = nil) -> [Seen] {
    var out: [Seen] = []
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    while let (el, depth) = stack.popLast(), out.count < limit {
        if depth > maxDepth { continue }
        let role = axText(el, kAXRoleAttribute as String) ?? "?"
        let subrole = axText(el, kAXSubroleAttribute as String) ?? ""
        if let r = axRect(el), r.width > 0, r.height > 0 {
            out.append(Seen(role: role, subrole: subrole, label: axLabel(el), rect: r,
                            depth: depth, el: el))
        }
        if let kids = axValue(el, kAXChildrenAttribute as String) as? [AXUIElement] {
            for kid in kids {
                if let want = onlyWindow,
                   axText(kid, kAXRoleAttribute as String) == "AXWindow",
                   !CFEqual(kid, want) { continue }
                stack.append((kid, depth + 1))
            }
        }
    }
    return out
}

/// Sheets and dialogs are what actually break an unattended run: they steal focus,
/// they sit on top of the thing you were about to click, and nothing about sending a
/// click reveals that one appeared.
func frontDialog() -> (title: String, buttons: [(String, CGRect)])? {
    guard let root = axRoot(nil) else { return nil }

    // A sheet is a child element with role AXSheet, not an attribute on the window.
    // Scanning the tree also catches dialog windows and alerts in one pass.
    let tree = axTree(root, limit: 2000)
    guard let panel = tree.first(where: {
        $0.role == "AXSheet" || $0.subrole == "AXDialog" || $0.subrole == "AXSystemDialog"
    }) else { return nil }

    // Buttons belonging to the panel are the ones sitting inside its rectangle.
    let buttons = tree.compactMap { seen -> (String, CGRect)? in
        guard seen.role == "AXButton", !seen.label.isEmpty,
              panel.rect.insetBy(dx: -4, dy: -4).contains(CGPoint(x: seen.rect.midX, y: seen.rect.midY))
        else { return nil }
        return (seen.label, seen.rect)
    }
    let title = tree.first(where: {
        $0.role == "AXStaticText" && !$0.label.isEmpty
            && panel.rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY))
    })?.label ?? panel.name
    return (title, buttons)
}

/// A hash of what the app publishes: every element's role, label and rectangle. This
/// is the honest way to ask "did anything change": exact, instant, and blind to
/// blinking carets, because a caret is not in the tree. Pixels are the fallback for
/// apps that publish nothing.
/// Some apps publish a tree but none of their content: a terminal drawing on the GPU
/// still exposes its menu bar and window. Trusting that tree means never seeing the
/// thing you care about, so the tree is only used when it carries text inside the
/// window itself.
func treeCarriesContent(_ tree: [Seen], window: CGRect?) -> Bool {
    guard let window = window else { return false }
    let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXStaticText", "AXCell", "AXRow"]
    return tree.contains { seen in
        textRoles.contains(seen.role) && !seen.label.isEmpty
            && window.insetBy(dx: -2, dy: -2).contains(CGPoint(x: seen.rect.midX, y: seen.rect.midY))
    }
}

func axStateHash(_ app: String?) -> UInt64? {
    guard let root = axRoot(app) else { return nil }
    let tree = axTree(root, limit: 3000)
    guard tree.count > 2, treeCarriesContent(tree, window: frontWindowRect()) else { return nil }
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ v: UInt64) { h = (h ^ v) &* 0x0000_0100_0000_01b3 }
    for seen in tree {
        for b in seen.role.utf8 { mix(UInt64(b)) }
        for b in seen.label.utf8 { mix(UInt64(b)) }
        mix(UInt64(bitPattern: Int64(Int(seen.rect.minX))))
        mix(UInt64(bitPattern: Int64(Int(seen.rect.minY))))
        mix(UInt64(bitPattern: Int64(Int(seen.rect.width))))
        mix(UInt64(bitPattern: Int64(Int(seen.rect.height))))
    }
    return h
}

/// What is in the field that has keyboard focus right now.
func focusedValue(_ app: String?) -> String? {
    guard let root = axRoot(app),
          let el = axValue(root, kAXFocusedUIElementAttribute as String),
          CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
    return axText(el as! AXUIElement, kAXValueAttribute as String)
}

/// The frontmost window's rectangle, so verification does not need hand-measured
/// coordinates. Falls back to the whole screen when no window can be found.
func frontWindowRect() -> CGRect? {
    guard let root = axRoot(nil) else { return nil }
    for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
        if let win = axValue(root, attr as String), CFGetTypeID(win) == AXUIElementGetTypeID(),
           let rect = axRect(win as! AXUIElement), rect.width > 0 {
            return rect
        }
    }
    return nil
}

func axRoot(_ appName: String?) -> AXUIElement? {
    let name = appName ?? frontmostApp()
    guard let app = runningApp(named: name) else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

/// Roles worth clicking. Everything else is scenery unless asked for by name.
let clickableRoles: Set<String> = [
    "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
    "AXTextField", "AXTextArea", "AXLink", "AXMenuItem", "AXTab", "AXSlider",
    "AXComboBox", "AXSearchField", "AXCell", "AXRow", "AXImage", "AXStaticText",
    "AXDisclosureTriangle", "AXIncrementor", "AXToolbar", "AXScrollBar"
]

/// Labels arrive with directional marks embedded — WhatsApp's are full of U+200E — and
/// one invisible character is enough to turn an exact match into a substring one, which
/// then loses to any container that merely starts with the same word. "Search" found a
/// group called "Search results" instead of the search field for exactly this reason.
func plain(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.filter {
        !(0x200B...0x200F).contains($0.value) && $0.value != 0xFEFF
    })).trimmingCharacters(in: .whitespaces).lowercased()
}

/// OCR confuses shapes, never meanings: l, I and 1 are the same few pixels, as are O and
/// 0. Folding them lets a match survive a misread. Only text that came from pixels is
/// folded — tree labels are exact and must stay that way, or "Sound" starts matching
/// "5ound" for no reason.
func confusable(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "l", "i", "|", "!": out.append("1")
        case "o": out.append("0")
        case "s": out.append("5")
        case "b": out.append("8")
        case "z": out.append("2")
        default: out.append(c)
        }
    }
    return out
}

func matches(_ s: Seen, needle: String, role: String?) -> Int? {
    if let want = role, s.role.lowercased() != want.lowercased() { return nil }
    guard !needle.isEmpty else { return role == nil ? nil : 1000 }
    let n = plain(needle)
    var best: Int?
    for hay in [plain(s.label), plain(s.name), plain(s.subrole)] where !hay.isEmpty {
        let score = hay == n ? 0 : hay.hasPrefix(n) ? 1 : hay.contains(n) ? 2 : nil
        if let sc = score, sc < (best ?? 99) { best = sc }
    }
    // Last resort, and only for text read off the screen.
    if best == nil, s.role == "AXOCRText", !plain(s.label).isEmpty,
       confusable(plain(s.label)).contains(confusable(n)) { best = 3 }
    return best
}

var useOCR = false
var ocrFast = false

/// An element can be published, correctly positioned, and still not be there: WhatsApp
/// draws its search results *over* a chat list it never takes down, so thirteen rows sit
/// under the panel at coordinates that now belong to whatever covers them. Clicking one
/// opens a different chat.
///
/// The tree cannot tell — both are equally real to it. Hit testing can, because it
/// answers with what a click would reach. It only speaks for the application in front,
/// so anything else is left alone rather than guessed at.
func reallyOnScreen(_ s: Seen, frontPid: pid_t?) -> Bool {
    guard let want = s.el, frontPid != nil else { return true }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                           Float(s.rect.midX), Float(s.rect.midY),
                                           &hit) == .success, var cur = hit else { return true }
    // The answer is the deepest element under the point, so a visible candidate is either
    // that one or one of its ancestors.
    for _ in 0..<12 {
        if CFEqual(cur, want) { return true }
        guard let parent = axValue(cur, kAXParentAttribute as String),
              CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
        cur = unsafeBitCast(parent, to: AXUIElement.self)
    }
    return false
}

/// Hit testing is only meaningful for the app that owns the screen right now.
func frontPidIfOwns(_ app: String?) -> pid_t? {
    guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
    if let want = app, !appMatches(front, want) { return nil }
    return front.processIdentifier
}

func find(_ needle: String, app: String?, role: String?, all: Bool) -> [Seen] {
    var seen: [Seen] = []
    if let root = axRoot(app) { seen = axTree(root, onlyWindow: focusedWindow(root)) }
    // Only reach for pixels when the tree cannot answer: it is slower and fallible.
    if useOCR && seen.allSatisfy({ matches($0, needle: needle, role: role) == nil }) {
        seen += cachedOCR(screen, fast: ocrFast)
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
    let ranked = scored.map { $0.1 }
    // Hit testing costs a round trip each, so only the leaders pay it and a list with
    // nothing occluded answers on the first one. Refusing beats returning a rectangle
    // that now belongs to whatever is drawn over it.
    let front = frontPidIfOwns(app)
    if all { return ranked.filter { reallyOnScreen($0, frontPid: front) } }
    return ranked.prefix(8).first { reallyOnScreen($0, frontPid: front) }.map { [$0] } ?? []
}

// ============================================================================
// Matching by appearance
//
// Text is not the only thing on a screen, and OCR cannot read an icon, a canvas, or a
// game. Matching a small reference image is what makes those targets findable: it does
// not care what the thing means, only what it looks like.
// ============================================================================

/// One byte per pixel, drawn through a grayscale context so any source format works.
func grayBuffer(_ img: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
    let w = img.width, h = img.height
    guard w > 0, h > 0 else { return nil }
    var pixels = [UInt8](repeating: 0, count: w * h)
    let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? (pixels, w, h) : nil
}

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Average k by k blocks into one pixel. Averaging, not sampling: a coarse pass that
/// point-samples every k-th pixel misses the true peak whenever it falls between grid
/// points, because a two-pixel shift on fine interface detail destroys correlation.
func downsample(_ buf: (pixels: [UInt8], width: Int, height: Int), by k: Int)
    -> (pixels: [UInt8], width: Int, height: Int) {
    guard k > 1 else { return buf }
    let w = buf.width / k, h = buf.height / k
    guard w > 0, h > 0 else { return buf }
    var out = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            var sum = 0
            for dy in 0..<k {
                let row = (y * k + dy) * buf.width + x * k
                for dx in 0..<k { sum += Int(buf.pixels[row + dx]) }
            }
            out[y * w + x] = UInt8(sum / (k * k))
        }
    }
    return (out, w, h)
}

/// Correlation of a template against one placement inside a larger buffer.
/// Normalised cross-correlation, not average pixel difference: on a dark screen almost
/// every region is within a few grey levels of every other, so a difference score calls
/// unrelated areas a 0.9 match. Correlation asks whether the *pattern* agrees and is
/// unmoved by overall brightness.
func correlate(_ t: (pixels: [UInt8], width: Int, height: Int),
               _ h: (pixels: [UInt8], width: Int, height: Int),
               atX ox: Int, y oy: Int) -> Double {
    var sumT = 0.0, sumH = 0.0, sumTT = 0.0, sumHH = 0.0, sumTH = 0.0
    let n = Double(t.width * t.height)
    for ty in 0..<t.height {
        let hrow = (oy + ty) * h.width + ox, trow = ty * t.width
        for tx in 0..<t.width {
            let tv = Double(t.pixels[trow + tx]), hv = Double(h.pixels[hrow + tx])
            sumT += tv; sumH += hv; sumTT += tv * tv; sumHH += hv * hv; sumTH += tv * hv
        }
    }
    guard n > 1 else { return -1 }
    let covar = sumTH - sumT * sumH / n
    let varT = sumTT - sumT * sumT / n
    let varH = sumHH - sumH * sumH / n
    // A flat patch has no pattern to agree with; refuse rather than score it high.
    guard varT > 1e-6, varH > 1e-6 else { return -1 }
    return covar / (varT * varH).squareRoot()
}

/// Where a reference image sits inside a larger one, and how sure we are.
/// Searched on an averaged pyramid, then refined at full resolution around the best
/// few candidates — a full-resolution sweep of a screen against a button is hundreds
/// of millions of comparisons.
func locate(template: (pixels: [UInt8], width: Int, height: Int),
            inside haystack: (pixels: [UInt8], width: Int, height: Int))
    -> (x: Int, y: Int, score: Double)? {
    let (tw, th) = (template.width, template.height)
    guard tw <= haystack.width, th <= haystack.height, tw > 1, th > 1 else { return nil }

    let k = max(1, min(min(tw, th) / 10, 8))
    let smallT = downsample(template, by: k)
    let smallH = downsample(haystack, by: k)
    guard smallT.width > 1, smallT.height > 1,
          smallH.width >= smallT.width, smallH.height >= smallT.height else { return nil }

    var candidates: [(x: Int, y: Int, score: Double)] = []
    for y in 0...(smallH.height - smallT.height) {
        for x in 0...(smallH.width - smallT.width) {
            candidates.append((x, y, correlate(smallT, smallH, atX: x, y: y)))
        }
    }
    guard !candidates.isEmpty else { return nil }
    candidates.sort { $0.score > $1.score }

    var best = (x: 0, y: 0, score: -1.0)
    for candidate in candidates.prefix(8) {
        let baseX = candidate.x * k, baseY = candidate.y * k
        for dy in -k...k {
            for dx in -k...k {
                let nx = baseX + dx, ny = baseY + dy
                guard nx >= 0, ny >= 0, nx <= haystack.width - tw, ny <= haystack.height - th
                else { continue }
                let score = correlate(template, haystack, atX: nx, y: ny)
                if score > best.score { best = (nx, ny, score) }
            }
        }
    }
    return best.score < -0.5 ? nil : best
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

/// A coarse grid of quantised brightness samples. Comparing how MANY cells differ,
/// rather than whether a single hash changed, is what separates a repaint from a
/// blinking caret: a caret moves one or two cells, a repaint moves dozens.
func signature(_ region: CGRect) -> [UInt8]? {
    guard let (img, _) = captureScreen(region) else { return nil }
    return signature(of: img)
}

/// Taking the signature from an image already in hand matters for more than speed: a
/// fingerprint and the text cached under it have to describe the *same* frame. Capturing
/// twice lets the screen move in between, which files one frame's text under another
/// frame's fingerprint and serves it back for as long as the entry lives.
func signature(of img: CGImage) -> [UInt8]? {
    guard let data = img.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data) else { return nil }
    let rowBytes = img.bytesPerRow, pixelBytes = max(1, img.bitsPerPixel / 8)
    let length = CFDataGetLength(data)
    // Cells are a fixed size in pixels, not a fixed count, so sensitivity does not
    // change with the size of the region being watched. A grid of fixed count means
    // two typed characters are obvious in a small field and invisible in a window.
    let cellPixels = 7
    let cellsX = min(max(img.width / cellPixels, 12), 260)
    let cellsY = min(max(img.height / cellPixels, 12), 260)
    var out: [UInt8] = []
    // Each cell averages its own area rather than poking a single pixel. Point samples
    // miss text entirely: strokes are one or two pixels wide and the samples are a
    // dozen apart, so nearly every one lands on the background between letters.
    out.reserveCapacity(cellsX * cellsY)
    for cy in 0..<cellsY {
        let y0 = img.height * cy / cellsY, y1 = max(y0 + 1, img.height * (cy + 1) / cellsY)
        for cx in 0..<cellsX {
            let x0 = img.width * cx / cellsX, x1 = max(x0 + 1, img.width * (cx + 1) / cellsX)
            var total = 0, count = 0
            var y = y0
            while y < y1 {
                var x = x0
                while x < x1 {
                    let o = y * rowBytes + x * pixelBytes
                    if o + 2 < length {
                        total += (Int(bytes[o]) + Int(bytes[o + 1]) + Int(bytes[o + 2])) / 3
                        count += 1
                    }
                    x += max(1, (x1 - x0) / 4)
                }
                y += max(1, (y1 - y0) / 4)
            }
            let mean = count > 0 ? total / count : 0
            out.append(UInt8(mean >> 2))          // quantised, so dithering is not news
        }
    }
    return out
}

/// A baseline is several samples of the same region. Cells that already disagree
/// across those samples are flickering on their own: a fading caret, an animation, a
/// spinner. They are masked out, and change is judged only on the cells that were
/// holding still. This is what separates a repaint from a blinking cursor; no
/// magnitude threshold can, because a caret is a large fraction of a small region and
/// a few typed characters are a tiny fraction of a large one.
struct Baseline {
    let reference: [UInt8]
    let stable: [Bool]

    var stableCount: Int { stable.filter { $0 }.count }

    /// A cell counts as moved only on a real brightness shift. Ink against background
    /// is dozens of grey levels; capture noise and antialiasing are one or two, and
    /// exact-equality comparison treats those as news.
    static let step: Int = 4

    /// An absolute count, not a percentage. A percentage cannot work across region
    /// sizes: two typed characters are a fifth of a small field and a rounding error
    /// of a whole window. Cells that flicker on their own are already excluded, so a
    /// few stable cells moving really is something happening.
    func changed(_ now: [UInt8]) -> Bool {
        guard now.count == reference.count, stableCount > 20 else { return false }
        var differing = 0
        for i in 0..<now.count where stable[i] {
            if abs(Int(now[i]) - Int(reference[i])) >= Baseline.step {
                differing += 1
                if differing >= 4 { return true }
            }
        }
        return false
    }
}

func baseline(_ region: CGRect, samples: Int = 4) -> Baseline? {
    var shots: [[UInt8]] = []
    for i in 0..<samples {
        guard let s = signature(region) else { continue }
        shots.append(s)
        if i + 1 < samples { nap(0.3) }
    }
    guard let first = shots.first, !first.isEmpty else { return nil }
    var stable = [Bool](repeating: true, count: first.count)
    for shot in shots.dropFirst() where shot.count == first.count {
        for i in 0..<first.count where abs(Int(shot[i]) - Int(first[i])) >= Baseline.step {
            stable[i] = false
        }
    }
    return Baseline(reference: first, stable: stable)
}

func fingerprint(_ region: CGRect) -> UInt64? {
    signature(region).map(fingerprint(of:))
}

func fingerprint(of sig: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for v in sig { h = (h ^ UInt64(v)) &* 0x0000_0100_0000_01b3 }
    return h
}

func cacheFile(_ name: String) -> String {
    let dir = NSHomeDirectory() + "/Library/Caches/human-input"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    // Bounded, because there is one file per distinct region watched and nothing else
    // ever removes them. Relying on the habit of watching few regions is not a bound.
    if let names = try? FileManager.default.contentsOfDirectory(atPath: dir), names.count > 60 {
        let stale = names.filter { $0.hasPrefix("ocr-") }.compactMap { file -> (String, Date)? in
            let path = dir + "/" + file
            let when = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            return (path, when ?? Date.distantPast)
        }.sorted { $0.1 < $1.1 }
        for (path, _) in stale.prefix(max(0, stale.count - 40)) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
    return dir + "/" + name
}

/// OCR costs seconds, so a region is only re-read when its fingerprint says it changed.
/// One capture serves both the fingerprint and the recognition, so the key and the text
/// filed under it always describe the same frame.
func cachedOCR(_ region: CGRect, fast: Bool) -> [Seen] {
    let tag = "ocr-\(Int(region.minX))-\(Int(region.minY))-\(Int(region.width))-\(Int(region.height)).json"
    let path = cacheFile(tag)
    guard let (img, scale) = captureScreen(region) else { return [] }
    let print = signature(of: img).map(fingerprint(of:))

    if let print = print, let raw = FileManager.default.contents(atPath: path),
       let blob = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
       let stamp = blob["fingerprint"] as? String, stamp == String(print),
       let rows = blob["lines"] as? [[String: Any]] {
        return rows.compactMap { row in
            guard let text = row["text"] as? String, let box = row["rect"] as? [Double], box.count == 4
            else { return nil }
            return Seen(role: "AXOCRText", subrole: "", label: text,
                        rect: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]), depth: 0)
        }
    }

    let lines = ocrRead(of: img, scale: scale, region: region, fast: fast)
    if let print = print {
        let blob: [String: Any] = ["fingerprint": String(print), "lines": lines.map {
            ["text": $0.label, "rect": [$0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height]]
        }]
        if let raw = try? JSONSerialization.data(withJSONObject: blob) {
            try? raw.write(to: URL(fileURLWithPath: path))
        }
    }
    return lines
}

func ocrRead(_ region: CGRect, fast: Bool) -> [Seen] {
    guard let (img, scale) = captureScreen(region) else { return [] }
    return ocrRead(of: img, scale: scale, region: region, fast: fast)
}

/// Vision needs a certain number of pixels per glyph before it will read one at all, and
/// UI text in a small region falls under it. Enlarging the picture is the honest fix —
/// lowering minimumTextHeight only makes it guess at shapes it still cannot see.
/// Normalised boxes come back in the same coordinates either way, so nothing downstream
/// has to know.
func upscaled(_ img: CGImage, by k: Int) -> CGImage {
    let w = img.width * k, h = img.height * k
    guard k > 1, w * h < 40_000_000,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return img }
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? img
}

func ocrRead(of img: CGImage, scale: CGFloat, region: CGRect, fast: Bool) -> [Seen] {
    let img = img.height < 300 ? upscaled(img, by: 3)
            : img.height < 800 ? upscaled(img, by: 2) : img
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
    var duration = (0.035 + 0.062 * difficulty) * Double.random(in: 0.82...1.3)
        * traits.pace * drift() / familiarHaste
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
    let tremorAmp = Double.random(in: 0.2...0.6) * traits.tremor * (device == "trackpad" ? 0.6 : 1)
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

/// A long reach across an unfamiliar screen is not always one throw at the target: the
/// hand sets off roughly the right way, the eyes catch up, and the back half is a fresh
/// aim. Somewhere you know well, you just go there.
let detourRate = 0.15
let detourReach = 400.0
/// Counted only so the selftest can prove the branch is still wired to something. A
/// decision nothing acts on passes every check about the decision.
var detoursTaken = 0

func wandersOnTheWay(from: CGPoint, to: CGPoint, familiar seen: Double) -> Bool {
    dist(from, to) > detourReach && skillGain(seen, ceiling: 0.3) < 1.15
        && Double.random(in: 0...1) < detourRate
}

/// Somewhere off the direct line, between a third and two thirds of the way across, on
/// either side. Being off the line is the whole point — the same trip twice should not
/// trace the same arc.
func detourWaypoint(from: CGPoint, to: CGPoint) -> CGPoint {
    let straight = dist(from, to)
    let dx = to.x - from.x, dy = to.y - from.y
    let len = max(CGFloat(straight), 1)
    let off = CGFloat(straight * Double.random(in: 0.12...0.3)) * (Bool.random() ? 1 : -1)
    let along = CGFloat(Double.random(in: 0.35...0.6))
    return onScreen(CGPoint(x: from.x + dx * along - dy / len * off,
                            y: from.y + dy * along + dx / len * off))
}

/// Aimed movement is not one smooth sweep to the exact pixel. It is a fast throw that
/// lands near the target, then one or two smaller corrections that close the gap, and
/// the miss grows with the distance thrown. That structure is what reads as a person.
func moveTo(_ target: CGPoint, width: Double = 26) {
    if dist(cursor(), target) < 1 { return }
    let close = max(width * 0.3, 1.6)

    let key = familiarKey(target)
    let seen = pointerPractice.seen(key)
    pointerPractice.record(key, after: seen)
    // Somewhere you go often, you stop checking your aim so carefully.
    familiarHaste = skillGain(seen, ceiling: 0.3)
    let attempts = seen >= 5 ? 1 : seen >= 1.5 ? 2 : 3
    defer { familiarHaste = 1 }

    if wandersOnTheWay(from: cursor(), to: target, familiar: seen) {
        detoursTaken += 1
        // Aimed loosely on purpose: a waypoint nobody is trying to hit is a fast throw.
        submove(from: cursor(), to: detourWaypoint(from: cursor(), to: target),
                width: 90, primary: true)
        nap(Double.random(in: 0.04...0.16))
    }

    for attempt in 0..<attempts {
        let here = cursor()
        let gap = dist(here, target)
        if gap <= close { break }

        let spread = device == "trackpad" ? 0.06 : 0.10
        let coverage = attempt == 0
            ? Double.random(in: (0.94 - spread)...(0.94 + spread))
            : Double.random(in: 0.55...1.1)
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
var fallible = false

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

var keyHeld: CGKeyCode?

/// Anything held when the process dies stays held: macOS keeps auto-repeating a key
/// whose key-up never arrived, and the user is left with a keyboard that types by
/// itself. Released on every exit path, including a signal.
func releaseEverythingHeld() {
    if let code = keyHeld {
        CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)?
            .post(tap: .cghidEventTap)
        keyHeld = nil
    }
    for (flag, code) in modifierKeys
    where CGEventSource.flagsState(.combinedSessionState).contains(flag) {
        let e = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)
        e?.type = .flagsChanged
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }
    if let (button, at) = buttonHeld {
        let type: CGEventType = button == .right ? .rightMouseUp
            : button == .center ? .otherMouseUp : .leftMouseUp
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: button)?
            .post(tap: .cghidEventTap)
        buttonHeld = nil
    }
}

func tapKey(_ code: CGKeyCode, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    if !dry {
        keyHeld = code
        down?.post(tap: .cghidEventTap)
    }
    nap(Double.random(in: 0.045...0.11))          // held, not instantaneous
    if !dry {
        up?.post(tap: .cghidEventTap)
        keyHeld = nil
    }
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
        if !dry {
            keyHeld = code
            down?.post(tap: .cghidEventTap)
        }
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
        if !dry {
            up?.post(tap: .cghidEventTap)
            keyHeld = nil
        }
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

var codeStyle = false

func emit(_ ch: Character, _ prev: inout Character?, _ base: Double) {
    typeUnicode(String(ch))
    var delay = iki(base) * handFactor(prev, ch)
    prev = ch

    // Writing pauses cluster into three components: word retrieval near 330ms,
    // phrase boundaries near 735ms, and planning pauses of a couple of seconds.
    if codeStyle {
        // Hunting for a bracket or an operator costs time before the key, not after.
        if "{}[]()<>|&$#@_".contains(ch) && Double.random(in: 0...1) < 0.5 {
            delay += 0.18 * exp(gauss() * 0.5)
        }
        if ch == "\n" { delay += Double.random(in: 0.1...0.4) }
    } else {
        if ch == " " && Double.random(in: 0...1) < 0.07 { delay += 0.33 * exp(gauss() * 0.4) }
        if ".,;:!?".contains(ch) && Double.random(in: 0...1) < 0.45 { delay += 0.74 * exp(gauss() * 0.4) }
    }
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

/// Code is not prose. It is symbol-heavy, comes in short bursts around identifiers,
/// pauses before punctuation rather than after it, and gets corrected more often.
func looksLikeCode(_ text: String) -> Bool {
    let symbols = text.filter { "{}[]()<>;=/\\|&*_$#@`~+".contains($0) }.count
    return Double(symbols) / Double(max(text.count, 1)) > 0.08
}

var typingStyle = "auto"

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
    // Fingers learn a string the way a hand learns a button. The tenth time you type a
    // path, a username or a command it comes out as one motion rather than as characters,
    // and you fumble it less. Speeding up the hand but never the fingers is the kind of
    // inconsistency that shows up in aggregate.
    let chunkKey = typingKey(text)
    let known = chunkKey.map { typingPractice.seen($0) } ?? 0
    let chunked = skillGain(known, ceiling: 0.35)
    let sureness = skillGain(known, ceiling: 0.5)
    if let key = chunkKey { typingPractice.record(key, after: known) }

    // 12/wpm is seconds per character at the stated rate. Corrections and the pause
    // mixture add time on top, so the base is pre-shrunk to land on the asked-for
    // net speed, and shrunk further in the modes that stop to fix mistakes.
    let base = (12.0 / max(wpm, 5)) * (accuracy == .clean ? 0.65 : 0.49) * drift() / chunked
    let chars = Array(text)
    // Corrections run about 6% of keystrokes, and roughly one error in six survives.
    let code = typingStyle == "code" || (typingStyle == "auto" && looksLikeCode(text))
    codeStyle = code
    let errorRate = accuracy == .clean ? 0.0
        : 0.055 * traits.errorScale * fatigueErrorScale() * (code ? 1.35 : 1) / sureness
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
    // A rehearsal adds delays up instead of living through them, so the clock it runs
    // against has to be the simulated one. Against a wall clock it would spin at full
    // speed for the whole duration instead of resting through it.
    let began = Date()
    let limit = minutes > 0 ? minutes * 60 : Double.infinity
    func running() -> Bool {
        (dry ? dryElapsed : Date().timeIntervalSince(began)) < limit
    }
    func log(_ s: String) {
        guard verbose else { return }
        FileHandle.standardError.write("human: \(s)\n".data(using: .utf8)!)
    }
    func napUntil(_ seconds: Double) {
        var left = seconds
        while left > 0 && running() { let s = min(left, 0.25); nap(s); left -= s }
    }

    var lastLeftAt = cursor()
    var firstPass = true
    log("idling on \(Int(screen.width))x\(Int(screen.height))")

    while running() {
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

        // Reading is not fidgeting near one spot. The pointer tracks along a line of
        // text and steps down to the next, and the page gets nudged along on the way.
        var readingLine: CGRect?
        if label == "reading", let root = axRoot(nil) {
            readingLine = axTree(root, limit: 400).filter {
                ($0.role == "AXStaticText" || $0.role == "AXTextArea")
                    && $0.rect.width > 120 && $0.rect.height < 400
            }.randomElement()?.rect
        }

        var travelled = 0.0
        for i in 0..<moves {
            if !running() { break }
            let from = cursor()
            let target: CGPoint
            if let line = readingLine {
                // Left to right across the text, dropping a line at a time.
                let across = Double(i + 1) / Double(moves + 1)
                target = onScreen(CGPoint(
                    x: line.minX + line.width * CGFloat(across * Double.random(in: 0.85...1.15)),
                    y: line.minY + min(line.height, 22) * CGFloat(i) + CGFloat(Double.random(in: -4...8))))
            } else if label == "reading" && i > 0 {
                target = onScreen(CGPoint(x: from.x + CGFloat(Double.random(in: -60...60)),
                                          y: from.y + CGFloat(Double.random(in: -40...40))))
            } else {
                target = idleTarget(near: from)
            }
            moveTo(target)
            // Nudge the page along, then read what arrived.
            if label == "reading" && Double.random(in: 0...1) < 0.35 {
                scroll(-Int.random(in: 60...180), over: nil)
                napUntil(Double.random(in: 0.8...3.0))
            }
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
// Model regression
//
// The behaviour model is the whole product, and it is all numbers. A curve that quietly
// turns back into a straight line throws nothing and breaks no command: it shows up only
// as runs that read wrong, months later, with no way left to tell when it started. So
// every curve is asserted here, and the build runs it.
// ============================================================================

func modelChecks() -> [(name: String, ok: Bool, detail: String)] {
    var out: [(name: String, ok: Bool, detail: String)] = []
    func check(_ name: String, _ ok: Bool, _ detail: String = "") { out.append((name, ok, detail)) }
    func rising(_ xs: [Double]) -> Bool { zip(xs, xs.dropFirst()).allSatisfy { $1 >= $0 - 1e-9 } }
    func falling(_ xs: [Double]) -> Bool { zip(xs, xs.dropFirst()).allSatisfy { $1 <= $0 + 1e-9 } }

    let gain = stride(from: 0.0, through: 120, by: 0.25).map { skillGain($0, ceiling: 0.3) }
    check("skill rises, flattens, and stops at its ceiling",
          abs(gain.first! - 1) < 1e-12 && rising(gain) && gain.last! < 1.3 && gain.last! > 1.2999
              && falling(zip(gain, gain.dropFirst()).map { $1 - $0 }),
          String(format: "1.0000 -> %.4f, always diminishing", gain.last!))

    let now = Date().timeIntervalSince1970
    let fortnight = practiced(Practice(visits: 60, lastAt: now - 14 * 86_400))
    let quarter = practiced(Practice(visits: 60, lastAt: now - 90 * 86_400))
    check("practice halves every fortnight and goes rusty",
          abs(practiced(Practice(visits: 60, lastAt: now)) - 60) < 0.01
              && abs(fortnight - 30) < 0.01 && quarter < 1
              && practiced(Practice(visits: 5, lastAt: now + 86_400)) == 5,
          String(format: "60 -> %.0f at a fortnight -> %.2f at ninety days", fortnight, quarter))

    let shape = stride(from: 0.0, through: 4000, by: 5).map { drift($0) }
    check("a session warms up, settles, then tires, within bounds",
          shape.first! > 1.0 && abs(shape.min()! - 1.0) < 1e-9 && shape.max()! <= 1.18 + 1e-9
              && rising(stride(from: 8.0, through: 4000, by: 5).map { drift($0) }),
          String(format: "%.3f start, %.3f floor, %.3f cap", shape.first!, shape.min()!, shape.max()!))

    let slips = stride(from: 0.0, through: 4000, by: 5).map { fatigueErrorScale($0) }
    check("tiredness costs accuracy too, and stops",
          slips.first! == 1 && rising(slips) && slips.max()! <= 1.45 + 1e-9
              && fatigueErrorScale(1000) > 1,
          String(format: "1.00 -> %.2f", slips.max()!))

    check("rest recovers gradually and eventually completely",
          recovered(200, resting: 0) == 200 && recovered(200, resting: 60) == 200
              && falling(stride(from: 0.0, through: 8 * 3600, by: 60).map { Double(recovered(200, resting: $0)) })
              && recovered(200, resting: 1320) == 100 && recovered(200, resting: 8 * 3600) == 0,
          String(format: "200 -> %d after 22min -> %d overnight",
                 recovered(200, resting: 1320), recovered(200, resting: 8 * 3600)))

    var lo = Double.infinity, hi = 0.0
    var distinct = Set<String>()
    for day in 20_000..<20_400 {
        let t = dayDrift(Traits(), day: day)
        lo = min(lo, t.pace); hi = max(hi, t.pace)
        distinct.insert(String(format: "%.5f", t.pace))
    }
    check("traits drift by the day inside a narrow band",
          lo >= 0.92 - 1e-9 && hi <= 1.08 + 1e-9 && distinct.count > 350
              && dayDrift(Traits(), seed: "ana", day: 300).pace == dayDrift(Traits(), seed: "ana", day: 300).pace
              && dayDrift(Traits(), seed: "ana", day: 300).pace != dayDrift(Traits(), seed: "ana", day: 301).pace,
          String(format: "%.3f..%.3f over 400 days, %d distinct", lo, hi, distinct.count))

    check("short strings do not chunk, and a string keys to itself",
          typingKey("ab") == nil && typingKey("git status") == typingKey("git status")
              && typingKey("git status") != typingKey("git commit -a"))

    let migrated = PracticeStore.parse(["old": 4, "new": [9.0, now - 14 * 86_400]])
    check("every format this cache has had still loads",
          migrated["old"]?.visits == 4 && migrated["new"]?.visits == 9
              && abs(practiced(migrated["new"]!) - 4.5) < 0.05
              && PracticeStore.parse(["x": "nonsense"]).isEmpty,
          "\(migrated.count) entries, junk dropped")

    // Sampled rather than reasoned about: these are random draws, and the property that
    // matters is where their means sit relative to each other.
    func meanGap(_ from: String?, _ to: String, since: Double, _ runs: Int = 4000) -> Double {
        let wasDry = dry, wasElapsed = dryElapsed
        dry = true
        var total = 0.0
        for _ in 0..<runs {
            dryElapsed = 0
            transitionPause(from: from, to: to, since: since)
            total += dryElapsed
        }
        dry = wasDry; dryElapsed = wasElapsed
        return total / Double(runs)
    }
    let flow = meanGap("click", "click", since: 0)
    let verb = meanGap("click", "scroll", since: 0)
    let hands = meanGap("click", "type", since: 0)
    let eyes = meanGap("find", "click", since: 0)
    check("gaps grow with the cost of the switch",
          flow < verb && verb < hands && hands < eyes,
          String(format: "flow %.2f < verb %.2f < hands %.2f < eyes %.2f", flow, verb, hands, eyes))
    check("a gap the caller already spent is not spent twice",
          meanGap("find", "click", since: 30) == 0 && meanGap(nil, "click", since: 30) == 0)
    check("looking at the screen costs no input time",
          meanGap("click", "find", since: 0) == 0 && meanGap("click", "check", since: 0) == 0)

    // Reading during work must not lengthen the run: it spends the comprehension pause
    // differently, it does not spend more of it.
    let budgets = [0.6, 1.2, 2.5, 4.0]
    let overrun = budgets.map { budget -> Double in
        let wasDry = dry, wasElapsed = dryElapsed
        dry = true
        var worst = 0.0
        for _ in 0..<200 {
            dryElapsed = 0
            readingDrift(budget)
            worst = max(worst, abs(dryElapsed - budget))
        }
        dry = wasDry; dryElapsed = wasElapsed
        return worst
    }
    check("reading spends the pause it was given, not more",
          overrun.allSatisfy { $0 < 0.01 },
          String(format: "worst drift %.4fs over %d budgets", overrun.max()!, budgets.count))

    // This one had never been seen to happen: it needs an unfamiliar target, a long
    // reach and a 15% roll, and the selftest's own targets go familiar after a few
    // builds, so it was getting less reachable over time rather than more.
    let near = CGPoint(x: 100, y: 100), far = CGPoint(x: 1000, y: 700)
    let fired = (0..<8000).filter { _ in wandersOnTheWay(from: near, to: far, familiar: 0) }.count
    check("a long unfamiliar reach wanders about one time in seven",
          abs(Double(fired) / 8000 - detourRate) < 0.02
              && !(0..<400).contains { _ in wandersOnTheWay(from: near, to: far, familiar: 40) }
              && !(0..<400).contains { _ in
                  wandersOnTheWay(from: near, to: CGPoint(x: near.x + 200, y: near.y), familiar: 0) },
          String(format: "%.3f of long reaches, never when short or familiar", Double(fired) / 8000))

    var offLine = 0.0, sides = Set<Bool>()
    for _ in 0..<2000 {
        let via = detourWaypoint(from: near, to: far)
        // Distance from the point to the straight line, by the cross product.
        let dx = far.x - near.x, dy = far.y - near.y
        let cross = (via.x - near.x) * dy - (via.y - near.y) * dx
        offLine = max(offLine, abs(Double(cross)) / dist(near, far))
        sides.insert(cross > 0)
    }
    check("the waypoint really leaves the straight line, either side",
          offLine > 0.1 * dist(near, far) && sides.count == 2,
          String(format: "up to %.0fpx off a %.0fpx line, both sides", offLine, dist(near, far)))

    // And that moveTo acts on the decision. A rehearsal posts no events but runs all of
    // the logic, so the branch is exercised without touching the screen.
    let from = cursor()
    let corner = CGPoint(x: from.x > screen.midX ? screen.minX + 40 : screen.maxX - 40,
                         y: from.y > screen.midY ? screen.minY + 40 : screen.maxY - 40)
    let cornerKey = familiarKey(corner)
    let heldCorner = pointerPractice.entries[cornerKey]
    pointerPractice.entries[cornerKey] = nil            // it has to read as unfamiliar
    let wasDry = dry, wasElapsed = dryElapsed, taken = detoursTaken
    dry = true
    for _ in 0..<300 { moveTo(corner) }
    dry = wasDry
    dryElapsed = wasElapsed
    pointerPractice.entries[cornerKey] = heldCorner
    check("moveTo acts on the detour it decided to take",
          dist(from, corner) > detourReach && detoursTaken - taken > 10,
          "\(detoursTaken - taken) of 300 rehearsed long reaches")

    if let key = typingKey("the quarterly numbers look right to me") {
        let held = typingPractice.entries[key]
        let wasDry = dry, wasElapsed = dryElapsed, wasBuffer = dryBuffer
        dry = true
        // Heavily sampled: the pause mixture has a long tail, and a mean over too few
        // runs makes this assertion flap rather than fail.
        func timeTyping(_ visits: Double, _ runs: Int = 500) -> Double {
            typingPractice.entries[key] = visits == 0 ? nil : Practice(visits: visits, lastAt: now)
            var total = 0.0
            for _ in 0..<runs {
                dryElapsed = 0
                dryBuffer = ""
                typeText("the quarterly numbers look right to me", wpm: 70, accuracy: .human)
                total += dryElapsed
            }
            return total / Double(runs)
        }
        let cold = timeTyping(0), warm = timeTyping(40)
        typingPractice.entries[key] = held        // the probe leaves no practice behind
        dry = wasDry; dryElapsed = wasElapsed; dryBuffer = wasBuffer
        check("a string typed often comes out as one motion",
              warm < cold * 0.88 && warm > cold * 0.55,
              String(format: "%.2fs cold -> %.2fs practised", cold, warm))
    }

    return out
}

// ============================================================================
// Recording
//
// Watch real input and write it out as a script. This is the half of the tool that
// needs no model at all: do the thing once by hand, replay it forever.
// ============================================================================

var recorded: [String] = []
var recordLastAt = Date()
var typeBuffer = ""
var pressedAt: CGPoint?
var scrollAccum = 0
var recordLastApp = ""
var recordDeadline = Date.distantFuture

let namesByCode: [CGKeyCode: String] = {
    var out: [CGKeyCode: String] = [:]
    for (name, code) in keyCodes where out[code] == nil { out[code] = name }
    return out
}()

func flushTyping() {
    guard !typeBuffer.isEmpty else { return }
    recorded.append("type \"\(typeBuffer.replacingOccurrences(of: "\"", with: ""))\"")
    typeBuffer = ""
}

func flushScroll() {
    guard scrollAccum != 0 else { return }
    let at = cursor()
    recorded.append("scroll \(scrollAccum) \(Int(at.x)) \(Int(at.y))")
    scrollAccum = 0
}

/// A pause you took is part of what you did, so it is recorded too.
func noteGap() {
    let gap = Date().timeIntervalSince(recordLastAt)
    recordLastAt = Date()
    if gap > 1.5 {
        flushTyping()
        flushScroll()
        recorded.append(String(format: "wait %.0f", min(gap, 30)))
    }
}

func noteApp() {
    let app = frontmostApp()
    guard !app.isEmpty, app != recordLastApp else { return }
    flushTyping()
    flushScroll()
    recorded.append("focus \(app)")
    recordLastApp = app
}

func chordName(_ flags: CGEventFlags, _ key: String) -> String {
    var parts: [String] = []
    if flags.contains(.maskControl) { parts.append("ctrl") }
    if flags.contains(.maskAlternate) { parts.append("opt") }
    if flags.contains(.maskShift) { parts.append("shift") }
    if flags.contains(.maskCommand) { parts.append("cmd") }
    parts.append(key)
    return parts.joined(separator: "+")
}

let recordTap: CGEventTapCallBack = { _, type, event, _ in
    let passthrough = Unmanaged.passUnretained(event)
    let flags = event.flags
    // The same combination that aborts a run also ends a recording.
    if flags.contains([.maskControl, .maskAlternate, .maskCommand]) {
        CFRunLoopStop(CFRunLoopGetCurrent())
        return passthrough
    }

    switch type {
    case .keyDown:
        noteGap()
        noteApp()
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modified = flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
        let named = namesByCode[code]
        let isText = !modified && ![36, 48, 53, 51, 123, 124, 125, 126].contains(Int(code))

        if isText {
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length,
                                           unicodeString: &chars)
            if length > 0 {
                typeBuffer += String(utf16CodeUnits: chars, count: length)
            }
        } else if let name = named {
            flushTyping()
            flushScroll()
            recorded.append("key \(chordName(flags, name))")
        }

    case .leftMouseDown, .rightMouseDown:
        noteGap()
        noteApp()
        flushTyping()
        flushScroll()
        pressedAt = event.location

    case .leftMouseUp, .rightMouseUp:
        let up = event.location
        let down = pressedAt ?? up
        pressedAt = nil
        let right = (type == .rightMouseUp)
        // A press and release far apart is a drag, not a click.
        if dist(down, up) > 8 {
            recorded.append("drag \(Int(down.x)) \(Int(down.y)) \(Int(up.x)) \(Int(up.y))")
        } else {
            let clicks = event.getIntegerValueField(.mouseEventClickState)
            var line = "click \(Int(up.x)) \(Int(up.y))"
            if right { line += " --right" }
            if clicks == 2 { line += " --double" }
            if clicks >= 3 { line += " --triple" }
            recorded.append(line)
        }
        recordLastAt = Date()

    case .scrollWheel:
        noteApp()
        scrollAccum += Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 10
        recordLastAt = Date()

    default:
        break
    }
    return passthrough
}

func recordSession(seconds: Double, into path: String?) {
    let mask = (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                      options: .listenOnly, eventsOfInterest: CGEventMask(mask),
                                      callback: recordTap, userInfo: nil) else {
        FileHandle.standardError.write(
            "human: cannot listen to input. Grant Input Monitoring in System Settings.\n"
                .data(using: .utf8)!)
        exit(3)
    }

    recordLastApp = frontmostApp()
    recorded.append("focus \(recordLastApp)")
    recordLastAt = Date()
    recordDeadline = seconds > 0 ? Date().addingTimeInterval(seconds) : Date.distantFuture

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    // A timer, because with no input the callback never runs and the deadline would
    // never be noticed.
    let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, Date().timeIntervalSinceReferenceDate,
                                                0.5, 0, 0) { _ in
        if Date() >= recordDeadline { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)

    FileHandle.standardError.write(
        "recording. do the thing, then hold control+option+command to stop.\n".data(using: .utf8)!)
    CFRunLoopRun()

    flushTyping()
    flushScroll()
    let script = recorded.joined(separator: "\n") + "\n"
    if let path = path {
        try? script.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        FileHandle.standardError.write(
            "wrote \(recorded.count) steps to \(path)\n".data(using: .utf8)!)
    } else {
        print(script, terminator: "")
    }
}

// ============================================================================
// CLI
// ============================================================================

var argv = Array(CommandLine.arguments.dropFirst())


// ============================================================================
// Work log
//
// Counts input, never content. How many keys were pressed is a measure of effort;
// which keys were pressed is a keylogger, and would capture passwords, bank details
// and other people's messages. There is no version of this worth building, so the
// key code is never looked at.
//
// Only events the HID layer reports are counted. This tool posts from a private
// source, so its own synthetic input is invisible here and cannot inflate a record
// that is meant to say a person was working.
// ============================================================================

var wlKeys = 0, wlLeft = 0, wlRight = 0, wlScroll = 0
var wlApps: Set<String> = []

let workTap: CGEventTapCallBack = { _, type, event, _ in
    if event.getIntegerValueField(.eventSourceStateID)
        == Int64(CGEventSourceStateID.hidSystemState.rawValue) {
        switch type {
        case .keyDown:        wlKeys += 1
        case .leftMouseDown:  wlLeft += 1
        case .rightMouseDown: wlRight += 1
        case .scrollWheel:    wlScroll += 1
        default: break
        }
    }
    return Unmanaged.passUnretained(event)
}

/// Seconds since the operating system last saw real input.
///
/// UNVERIFIED: this reads back near zero even when nothing is being touched, so it is
/// probably picking the first of several HIDIdleTime entries and landing on a device
/// that never goes quiet. Trust `active`, which is derived from the counts, until this
/// has been watched across a genuinely idle machine.
func hidIdle() -> Double {
    let out = run("/usr/sbin/ioreg", ["-c", "IOHIDSystem"]).out
    guard let line = out.split(separator: "\n").first(where: { $0.contains("HIDIdleTime") }),
          let raw = line.split(separator: "=").last,
          let ns = Double(raw.trimmingCharacters(in: .whitespaces)) else { return 0 }
    return ns / 1_000_000_000
}

func frontWindowTitle() -> String {
    guard let root = axRoot(nil), let win = focusedWindow(root) else { return "" }
    return axText(win, kAXTitleAttribute as String) ?? ""
}

func runWorkLog(interval: Double, minutes: Double, path: String, titles: Bool) {
    requireTrust("watch input")
    let mask = (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                      options: .listenOnly, eventsOfInterest: CGEventMask(mask),
                                      callback: workTap, userInfo: nil) else {
        FileHandle.standardError.write(
            "human: cannot listen to input. Grant Input Monitoring in System Settings.\n"
                .data(using: .utf8)!)
        exit(3)
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    // A header line, so a reader knows how the numbers were produced rather than
    // having to assume. Counts mean nothing without the interval they were counted over.
    if !FileManager.default.fileExists(atPath: path) {
        let head = #"{"kind":"header","interval":\#(interval),"titles":\#(titles),"counts":"real HID input only","content":"never recorded"}"#
        try? (head + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    let stamp = ISO8601DateFormatter()
    let deadline = minutes > 0 ? Date().addingTimeInterval(minutes * 60) : Date.distantFuture
    var samples = 0
    FileHandle.standardError.write("human: work log -> \(path), every \(Int(interval))s. ctrl-c to stop.\n".data(using: .utf8)!)

    while Date() < deadline {
        let until = Date().addingTimeInterval(interval)
        while Date() < until {
            RunLoop.current.run(until: min(until, Date().addingTimeInterval(0.25)))
            panicCheck()
        }
        let app = frontmostApp()
        wlApps.insert(app)
        let acted = wlKeys + wlLeft + wlRight + wlScroll
        var row: [String: Any] = [
            "t": stamp.string(from: Date()),
            "app": app,
            "keys": wlKeys, "clicks": wlLeft, "rightClicks": wlRight, "scrolls": wlScroll,
            "idle": Double(round(hidIdle() * 10) / 10),
            "active": acted > 0,
        ]
        if titles {
            let title = frontWindowTitle()
            if !title.isEmpty { row["title"] = title }
        }
        if let data = try? JSONSerialization.data(withJSONObject: row),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            }
        }
        samples += 1
        wlKeys = 0; wlLeft = 0; wlRight = 0; wlScroll = 0
    }
    FileHandle.standardError.write("human: \(samples) samples across \(wlApps.count) apps\n".data(using: .utf8)!)
}

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

func parseRegion(_ spec: String) -> CGRect? {
    let n = spec.split(separator: ",").compactMap { Double($0) }
    guard n.count == 4 else { return nil }
    return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
}

func point(_ a: String?, _ b: String?) -> CGPoint? {
    guard let a = a, let b = b, let x = Double(a), let y = Double(b) else { return nil }
    return CGPoint(x: x, y: y)
}

let usage = """
human - drive macOS the way a person does, and read the screen three ways

  see
    human check                     every permission gate, screen, cursor, held keys
    human where / human front       cursor position, name of the frontmost app
    human see [--app X] [--role R]  everything on screen, with coordinates
    human find "Save" [--app X] [--ocr]     coordinates of a named thing
    human read [--region x,y,w,h] [--fast]  read the screen with OCR
    human pane list|read <id>|send <id> "text" [--enter]|waitfor <id> "pattern"
    human waitfor "Done" [--gone] [--timeout 20]
    human dialog check|dismiss [--button "Don't Save"]
                                    report or clear a sheet sitting on top
    human state [--app X]           fingerprint of what an app publishes, for change checks
    human changed [x,y,w,h] [--timeout 3]   wait until a region, or the front window, repaints

  act
    human focus <AppName>           bring an app forward, wait until it really is
    human window where|move <dx> <dy>|place <x> <y>|resize <dw> <dh>
                                    drag the front window by its title bar or corner
    human move <x> <y>
    human click <x y | "name"> [--right --middle --double --triple --precise --hold s]
    human drag <x1> <y1> <x2> <y2> [--precise]
    human scroll <amount> [x y] [--horizontal]     negative scrolls down
    human type "text" [--wpm 70] [--accuracy clean|human|raw] [--keys] [--verify]
    human key <chord> [--repeat N] [--hold s]      e.g. cmd+a, shift+right
    human text select all|line|word|to-end | replace "new" | find "needle"
    human gesture pinch <amount> | swipe <amount>      attempted, not all apps listen
    human open <AppName> / human wait <seconds>
    human idle [--minutes N] [--no-yield]
    human plan <file|->             read the steps in plain words, touching nothing
    human record [--seconds N] [-o file.human]
                                    watch what you do and write it out as a script
    human run <file|-> [--confirm] [--dry] [--verbose]
                                    --confirm shows the plan and asks before acting

  keep it safe
    --require <AppName>             refuse to act unless that app is frontmost
    --dry                           rehearse, touch nothing
    --expect-change [x,y,w,h] | --expect "text" [--retry N] [--recover]
                                    region defaults to the frontmost window
                                    prove the action landed, repeat it if not
    human stop / human go           set or clear the abort flag
    human unstick                   release anything left held down
    every action is appended to ~/Library/Logs/human-input.log
    human selftest                  prove pointer, typing, sight and every model curve

  who is typing
    --persona <name>                one consistent hand: speed, curve bias, slips
    --device mouse|trackpad

Every action carries its own delays, and so does the gap between two of them: what the
caller already spent thinking counts towards it, and the rest is filled in. Aim, pace and
slips drift by the day, targets you use often get quicker and go rusty when you stop, so
the same flow run twice is never the same shape twice.
"""

// Unbuffered, so the plan and the prompt appear before the steps they describe when
// the output is piped rather than sitting in a terminal.
setvbuf(stdout, nil, _IONBF, 0)

atexit { releaseEverythingHeld(); savePractice(); saveSession() }
// A signal handler may not allocate or post events, so it only raises a flag and the
// cleanup happens in normal context, at the next pause.
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig) { _ in terminateRequested = 1 }
}

guard let cmd = argv.first else { print(usage); exit(0) }
argv.removeFirst()

/// An action that cannot tell whether it worked is a guess. Anything can be asked to
/// prove its effect, and to try again when it cannot.
func verify(against before: Baseline?, region: CGRect?, expectText: String?,
            app: String?, timeout: Double, axBefore: UInt64? = nil) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        // The tree first: exact, instant, and a caret is not in it. Pixels only when
        // the app publishes nothing worth reading.
        if let start = axBefore, let now = axStateHash(app), now != start { return true }
        if let region = region, let start = before {
            if let now = signature(region), start.changed(now) {
                nap(0.35)
                if let again = signature(region), start.changed(again) { return true }
            }
        }
        if let needle = expectText, !find(needle, app: app, role: nil, all: false).isEmpty { return true }
        nap(0.3)
    }
    return false
}

func execute(_ cmd: String, _ rest: [String]) {
    let saved = argv
    argv = rest
    defer { argv = saved }
    if !dry && !offstage.contains(cmd) { touched = true }
    switch cmd {
    case "check", "where", "front", "see", "find", "read", "state", "dialog", "selftest":
        break                                   // reads are not worth logging
    default:
        if !dry { session.actions += 1 }
        audit("\(cmd) \(rest.joined(separator: " ")) [front: \(frontmostApp())]")
    }
    if let want = takeValue("--require") { requiredApp = want }
    if takeFlag("--precise") { precise = true }
    if takeFlag("--fallible") { fallible = true }
    if takeFlag("--ocr") { useOCR = true }
    if let d = takeValue("--device") { device = d }
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
        // Reported from the hardware's own view, so a key stuck here is the keyboard
        // itself, not anything this tool posted.
        let stuckKeys = (CGKeyCode(0)...CGKeyCode(127))
            .filter { CGEventSource.keyState(.hidSystemState, key: $0) }
        print("keys held (hardware): \(stuckKeys.isEmpty ? "none" : stuckKeys.map(String.init).joined(separator: ", "))")
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
        for s in axTree(root, onlyWindow: everything ? nil : focusedWindow(root)) {
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
            if dry { nap(min(timeout, 2)); break }
            let deadline = Date().addingTimeInterval(timeout)
            var seen = false
            while Date() < deadline {
                if paneMatches(paneText(id), pattern) != gone { seen = true; break }
                nap(1.0)
            }
            if !seen {
                FileHandle.standardError.write("human: pane \(id) never \(gone ? "cleared" : "showed") '\(pattern)'\n".data(using: .utf8)!)
                exit(6)
            }
        default:
            FileHandle.standardError.write("human: pane list|read|send|waitfor\n".data(using: .utf8)!)
            exit(2)
        }

    case "window":
        let sub = argv.first ?? "where"
        if !argv.isEmpty { argv.removeFirst() }
        guard let rect = frontWindowRect() else {
            FileHandle.standardError.write("human: no front window\n".data(using: .utf8)!); exit(1)
        }
        // The title bar, clear of the traffic lights on the left.
        let grip = CGPoint(x: rect.midX, y: rect.minY + 12)
        switch sub {
        case "where":
            print("\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
        case "move":
            guard argv.count >= 2, let dx = Double(argv[0]), let dy = Double(argv[1]) else {
                FileHandle.standardError.write("human: window move needs <dx> <dy>\n".data(using: .utf8)!); exit(2)
            }
            drag(from: grip, to: CGPoint(x: grip.x + CGFloat(dx), y: grip.y + CGFloat(dy)))
        case "place":
            guard argv.count >= 2, let x = Double(argv[0]), let y = Double(argv[1]) else {
                FileHandle.standardError.write("human: window place needs <x> <y>\n".data(using: .utf8)!); exit(2)
            }
            drag(from: grip, to: CGPoint(x: CGFloat(x) + rect.width / 2, y: CGFloat(y) + 12))
        case "resize":
            guard argv.count >= 2, let dw = Double(argv[0]), let dh = Double(argv[1]) else {
                FileHandle.standardError.write("human: window resize needs <dw> <dh>\n".data(using: .utf8)!); exit(2)
            }
            precise = true          // a resize edge is about 4px, aim jitter is wider
            drag(from: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1),
                 to: CGPoint(x: rect.maxX - 1 + CGFloat(dw), y: rect.maxY - 1 + CGFloat(dh)))
        default:
            FileHandle.standardError.write("human: window where|move|place|resize\n".data(using: .utf8)!); exit(2)
        }

    case "dialog":
        let sub = argv.first ?? "check"
        if !argv.isEmpty && !argv[0].hasPrefix("--") { argv.removeFirst() }
        guard let found = frontDialog() else {
            if sub == "check" { print("none"); exit(1) }
            break                             // nothing to dismiss is not a failure
        }
        switch sub {
        case "check":
            print("\(found.title)")
            for (label, rect) in found.buttons {
                print("  \(Int(rect.midX)),\(Int(rect.midY))\t\(label)")
            }
        case "dismiss":
            let wanted = takeValue("--button")
            if let wanted = wanted,
               let hit = found.buttons.first(where: { $0.0.localizedCaseInsensitiveContains(wanted) }) {
                click(at: CGPoint(x: hit.1.midX, y: hit.1.midY))
                print("clicked \(hit.0)")
            } else if wanted == nil, let safe = found.buttons.first(where: {
                ["cancel", "don't save", "dont save", "later", "not now", "close"]
                    .contains($0.0.lowercased())
            }) {
                // Prefer the choice that changes nothing. Never press the one that
                // commits: a dialog appeared because something unexpected happened.
                click(at: CGPoint(x: safe.1.midX, y: safe.1.midY))
                print("clicked \(safe.0)")
            } else {
                pressKey("escape", extra: [])
                print("pressed escape")
            }
        default:
            FileHandle.standardError.write("human: dialog check|dismiss [--button X]\n".data(using: .utf8)!)
            exit(2)
        }

    case "text":
        let what = argv.first ?? ""
        if !argv.isEmpty { argv.removeFirst() }
        switch what {
        case "select":
            switch argv.first ?? "all" {
            case "all": pressKey("cmd+a", extra: [])
            case "line": pressKey("cmd+left", extra: []); pressKey("shift+cmd+right", extra: [])
            case "word": click(at: nil, button: .left, times: 2)
            case "to-end": pressKey("shift+cmd+down", extra: [])
            default:
                FileHandle.standardError.write("human: text select all|line|word|to-end\n".data(using: .utf8)!)
                exit(2)
            }
        case "replace":
            // Whatever is selected is replaced by typing over it, exactly as a person does.
            let with = argv.dropFirst(0).joined(separator: " ")
            guard !with.isEmpty else {
                FileHandle.standardError.write("human: text replace needs the new text\n".data(using: .utf8)!)
                exit(2)
            }
            typeText(with, wpm: traits.wpm, accuracy: .clean)
        case "find":
            let needle = argv.joined(separator: " ")
            guard !needle.isEmpty else {
                FileHandle.standardError.write("human: text find needs something to look for\n".data(using: .utf8)!)
                exit(2)
            }
            pressKey("cmd+f", extra: [])
            nap(Double.random(in: 0.3...0.6))
            typeText(needle, wpm: traits.wpm, accuracy: .clean)
            pressKey("return", extra: [])
            nap(Double.random(in: 0.2...0.5))
            pressKey("escape", extra: [])
        default:
            FileHandle.standardError.write("human: text select|replace|find\n".data(using: .utf8)!)
            exit(2)
        }

    case "gesture":
        // Magnify and swipe are not in the public event API. The type numbers are
        // stable and widely used, but an app is free to ignore them, so this is
        // attempted rather than promised.
        let kind = argv.first ?? ""
        if !argv.isEmpty { argv.removeFirst() }
        let amount = Double(argv.first ?? "") ?? 1
        requireTrust("gestures")
        switch kind {
        case "pinch", "zoom":
            let steps = 14
            for i in 1...steps {
                guard let e = CGEvent(source: nil) else { break }
                e.type = CGEventType(rawValue: 29)!          // magnify
                e.setDoubleValueField(CGEventField(rawValue: 113)!, value: amount / Double(steps))
                e.location = cursor()
                e.post(tap: .cghidEventTap)
                nap(0.012 * Double.random(in: 0.85...1.2))
                _ = i
            }
        case "swipe":
            guard let e = CGEvent(source: nil) else { break }
            e.type = CGEventType(rawValue: 31)!              // swipe
            e.setDoubleValueField(CGEventField(rawValue: 115)!, value: amount)
            e.location = cursor()
            e.post(tap: .cghidEventTap)
        default:
            FileHandle.standardError.write("human: gesture pinch <amount> | swipe <amount>\n".data(using: .utf8)!)
            exit(2)
        }

    case "worklog":
        let every = Double(takeValue("--interval") ?? "") ?? 15
        let mins = Double(takeValue("--minutes") ?? "") ?? 0
        let noTitles = takeFlag("--no-titles")
        let out = takeValue("-o") ?? takeValue("--out")
            ?? NSHomeDirectory() + "/Library/Logs/human-worklog.jsonl"
        runWorkLog(interval: every, minutes: mins, path: out, titles: !noTitles)

    case "record":
        let seconds = Double(takeValue("--seconds") ?? "") ?? 0
        recordSession(seconds: seconds, into: takeValue("-o") ?? takeValue("--out"))

    case "snip":
        // Capture a reference image now so it can be found again later.
        guard let spec = argv.first, let region = parseRegion(spec) else {
            FileHandle.standardError.write("human: snip needs x,y,w,h\n".data(using: .utf8)!); exit(2)
        }
        argv.removeFirst()
        let out = takeValue("-o") ?? takeValue("--out") ?? "snip.png"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-R",
                       "\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))", out]
        try? p.run()
        p.waitUntilExit()
        print(out)

    case "find-image":
        guard let file = argv.first else {
            FileHandle.standardError.write("human: find-image needs a png\n".data(using: .utf8)!); exit(2)
        }
        argv.removeFirst()
        let threshold = Double(takeValue("--threshold") ?? "") ?? 0.92
        let region = takeValue("--region").flatMap(parseRegion) ?? screen
        guard let templateImage = loadImage(file), let template = grayBuffer(templateImage) else {
            FileHandle.standardError.write("human: could not read \(file)\n".data(using: .utf8)!); exit(2)
        }
        // --in searches a saved image instead of the screen, which makes the matcher
        // testable against a known answer rather than only against a live display.
        var scale: CGFloat = 1
        var haystackImage: CGImage?
        if let file = takeValue("--in") {
            haystackImage = loadImage(file)
            if haystackImage == nil {
                FileHandle.standardError.write("human: could not read \(file)\n".data(using: .utf8)!); exit(2)
            }
        } else if let (shot, s) = captureScreen(region) {
            haystackImage = shot
            scale = s
        }
        guard let shot = haystackImage, let haystack = grayBuffer(shot) else {
            FileHandle.standardError.write("human: could not capture the screen\n".data(using: .utf8)!); exit(1)
        }
        guard let hit = locate(template: template, inside: haystack) else {
            FileHandle.standardError.write("human: the reference is larger than the search area\n".data(using: .utf8)!)
            exit(2)
        }
        if hit.score < threshold {
            FileHandle.standardError.write(String(format: "human: best match only %.2f, below %.2f\n",
                                                  hit.score, threshold).data(using: .utf8)!)
            exit(1)
        }
        // Back to screen points: the capture is at device resolution.
        let originX = takeFlag("--pixels") ? 0 : region.minX
        let originY = takeFlag("--pixels") ? 0 : region.minY
        let cx = originX + (Double(hit.x) + Double(template.width) / 2) / Double(scale)
        let cy = originY + (Double(hit.y) + Double(template.height) / 2) / Double(scale)
        if takeFlag("--score") {
            print(String(format: "%d %d %.3f", Int(cx), Int(cy), hit.score))
        } else {
            print("\(Int(cx)) \(Int(cy))")
        }

    case "pixel":
        // The cheapest state check there is: what colour is this point.
        guard let at = point(argv.first, argv.dropFirst().first) else {
            FileHandle.standardError.write("human: pixel needs <x> <y>\n".data(using: .utf8)!); exit(2)
        }
        guard let (shot, _) = captureScreen(CGRect(x: at.x, y: at.y, width: 1, height: 1)),
              let data = shot.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              CFDataGetLength(data) >= 3 else {
            FileHandle.standardError.write("human: could not read that pixel\n".data(using: .utf8)!); exit(1)
        }
        print(String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]))

    case "state":
        // A cheap fingerprint of what the app publishes, for scripts that want to ask
        // "has anything changed" without touching pixels.
        guard let h = axStateHash(takeValue("--app")) else {
            FileHandle.standardError.write("human: that app publishes no usable tree\n".data(using: .utf8)!)
            exit(1)
        }
        print(h)

    case "changed":
        // With no region given, watch the window in front. Hand-measured coordinates
        // are the fragile part of any of this.
        // Flags first, so a bare `human changed --timeout 5` does not read the flag
        // itself as the region.
        let timeout = Double(takeValue("--timeout") ?? "") ?? 3
        let given = takeValue("--region") ?? argv.first.flatMap { $0.hasPrefix("--") ? nil : $0 }
        let region = given.flatMap(parseRegion) ?? (given == nil ? (frontWindowRect() ?? screen) : nil)
        guard let region = region else {
            FileHandle.standardError.write("human: changed needs x,y,w,h or no argument for the front window\n"
                .data(using: .utf8)!); exit(2)
        }
        if dry { nap(min(timeout, 2)); break }
        guard let before = baseline(region) else {
            FileHandle.standardError.write("human: could not read that region\n".data(using: .utf8)!); exit(1)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var moved = false
        while Date() < deadline {
            nap(0.2)
            // Confirmed a beat later: a rendering blip does not survive a second look,
            // a repaint does.
            if let now = signature(region), before.changed(now) {
                nap(0.35)
                if let again = signature(region), before.changed(again) { moved = true; break }
            }
        }
        guard moved else { print("unchanged"); exit(1) }
        print("changed")

    case "read":
        var region = screen
        if let spec = takeValue("--region") {
            let n = spec.split(separator: ",").compactMap { Double($0) }
            if n.count == 4 { region = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
        }
        // Through the cache, so reading the same unchanged region twice costs one capture
        // and no recognition at all.
        let lines = cachedOCR(region, fast: ocrFast)
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
        // A rehearsal must not really sit and poll: it would spend the whole timeout
        // and then report a failure for something that was never going to happen.
        if dry { nap(min(timeout, 2)); break }
        // Succeeding returns to the caller rather than exiting: inside a script the
        // steps run in this same process, and exit(0) here would silently end the run
        // with a success code partway through.
        let deadline = Date().addingTimeInterval(timeout)
        var arrived = false
        while Date() < deadline {
            let there = !find(needle, app: app, role: role, all: false).isEmpty
            if there != untilGone {
                nap(Double.random(in: 0.2...0.5))     // a person does not react instantly
                arrived = true
                break
            }
            nap(0.25)
        }
        if !arrived {
            FileHandle.standardError.write(
                "human: waited \(Int(timeout))s, '\(needle)' never \(untilGone ? "went away" : "appeared")\n"
                    .data(using: .utf8)!)
            exit(6)
        }

    case "unstick":
        // An aborted command can leave a modifier or a button down, and everything
        // afterwards behaves strangely for reasons that are invisible.
        var cleared: [String] = []
        // Every key, not just the ones this tool presses: a key-down without its
        // key-up leaves macOS auto-repeating forever, whatever put it there.
        for code in CGKeyCode(0)...CGKeyCode(127)
        where CGEventSource.keyState(.combinedSessionState, key: code) {
            CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)?
                .post(tap: .cghidEventTap)
            cleared.append("key \(code)")
            nap(0.02)
        }
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
        if dry {
            FileHandle.standardError.write("  would focus \(name)\n".data(using: .utf8)!)
            break
        }
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
            // Off by a hair, notice, correct. Opt-in, because a stray click lands on
            // whatever is actually there.
            // Fitts again: the smaller the target, the likelier the miss. A flat 3%
            // chance is decoration; error rate is a property of the target.
            let smallest = min(hit.rect.width, hit.rect.height)
            let missChance = min(max(0.02 * (24 / max(smallest, 6)), 0.004), 0.14)
            if fallible && Double.random(in: 0...1) < missChance {
                let missX = hit.centre.x + CGFloat(hit.rect.width * Double.random(in: 0.6...0.85))
                click(at: CGPoint(x: missX, y: hit.centre.y), button: .left, times: 1)
                nap(Double.random(in: 0.35...0.9))          // the pause of noticing
            }
        }
        let next = takeValue("--next").flatMap { spec -> CGPoint? in
            let n = spec.split(separator: ",").compactMap { Double($0) }
            return n.count == 2 ? CGPoint(x: n[0], y: n[1]) : nil
        }
        click(at: t, button: right ? .right : middle ? .center : .left,
              times: triple ? 3 : double ? 2 : 1, modifiers: clickMods, holdFor: holdFor)
        // A hand does not park where it clicked; it starts drifting toward whatever
        // it is going to do next.
        if let next = next {
            let here = cursor()
            let lead = Double.random(in: 0.15...0.4)
            moveTo(CGPoint(x: here.x + (next.x - here.x) * CGFloat(lead),
                           y: here.y + (next.y - here.y) * CGFloat(lead)))
        }

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
        if let style = takeValue("--style") { typingStyle = style }
        let readBack = takeFlag("--verify")
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
            // Reading the field back is the only way to know the text really landed.
            // Autocorrect can rewrite a word while a correction is still in flight, and
            // nothing about sending the keystrokes reveals that.
            if readBack && !dry {
                nap(Double.random(in: 0.2...0.45))
                guard let got = focusedValue(requiredApp) else {
                    FileHandle.standardError.write(
                        "human: typed, but the field publishes no value to check\n".data(using: .utf8)!)
                    exit(9)
                }
                // Case-insensitive, because apps capitalise the first letter of a
                // sentence themselves. A dropped or wrong letter still fails.
                if got.range(of: text, options: .caseInsensitive) == nil {
                    FileHandle.standardError.write(
                        "human: typed text did not land. wanted \"\(text)\", field holds \"\(got.suffix(120))\"\n"
                            .data(using: .utf8)!)
                    exit(9)
                }
            }
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
        var minutes = Double(takeValue("--minutes") ?? "") ?? 0
        // A rehearsal accumulates time instead of living through it, so an unbounded
        // idle would spin at full speed forever rather than resting.
        if dry && minutes == 0 { minutes = 5 }
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

        // Retried, because a hand on the mouse mid-test looks exactly like a failure
        // and this check is about the tool's aim, not the user's.
        var worst = 0.0
        for t in [CGPoint(x: 260, y: 220), CGPoint(x: screen.maxX - 180, y: screen.maxY - 160),
                  CGPoint(x: screen.midX, y: screen.midY)] {
            var best = Double.infinity
            for _ in 0..<3 {
                moveTo(t)
                best = min(best, dist(cursor(), t))
                if best < 5 { break }
            }
            worst = max(worst, best)
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

        // The behaviour model, asserted rather than eyeballed.
        for c in modelChecks() { check(c.name, c.ok, c.detail) }

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

/// A step written in the words a person would use, so a plan can be read and agreed to
/// before anything touches the machine. The whole point of showing a plan is that it is
/// legible; printing the raw command back is not a plan.
func describe(_ cmd: String, _ args: [String]) -> String {
    func val(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    // Skipping the flags is not enough: their values are arguments too, and a leaked
    // "--require TextEdit" turns into text the plan claims will be typed.
    let takesValue: Set<String> = [
        "--require", "--app", "--role", "--wpm", "--accuracy", "--style", "--persona",
        "--device", "--timeout", "--expect", "--expect-timeout", "--retry", "--button",
        "--region", "--limit", "--minutes", "--repeat", "--hold", "--next"
    ]
    var plain: [String] = []
    var skip = false
    for (i, a) in args.enumerated() {
        if skip { skip = false; continue }
        if a == "--expect-change" {
            // its value is optional, and only present when it parses as a region
            if i + 1 < args.count, parseRegion(args[i + 1]) != nil { skip = true }
            continue
        }
        if a.hasPrefix("--") { skip = takesValue.contains(a); continue }
        plain.append(a)
    }
    let quoted = plain.joined(separator: " ")
    var line: String

    switch cmd {
    case "focus": line = "bring \(quoted) to the front"
    case "open": line = "open \(quoted)"
    case "move": line = "move the pointer to \(quoted)"
    case "click":
        let what = plain.count >= 2 && Double(plain[0]) != nil ? "at \(plain.joined(separator: ","))"
                                                              : "on \"\(quoted)\""
        let kind = args.contains("--double") ? "double click" : args.contains("--right") ? "right click"
                 : args.contains("--triple") ? "triple click" : "click"
        line = "\(kind) \(what)"
    case "drag": line = "drag from \(plain.prefix(2).joined(separator: ",")) to \(plain.dropFirst(2).joined(separator: ","))"
    case "scroll":
        let n = Int(plain.first ?? "0") ?? 0
        line = "scroll \(n < 0 ? "down" : "up") \(abs(n))px"
    case "type": line = "type \"\(quoted)\""
    case "key": line = "press \(quoted)"
    case "text": line = "\(plain.first ?? "") text \(plain.dropFirst().joined(separator: " "))"
    case "window": line = "\(plain.first ?? "") the window \(plain.dropFirst().joined(separator: " "))"
    case "waitfor":
        line = "wait until \"\(quoted)\" \(args.contains("--gone") ? "goes away" : "appears")"
    case "pane":
        let sub = plain.first ?? ""
        line = sub == "send" ? "write into terminal pane \(plain.dropFirst().joined(separator: " "))"
             : sub == "waitfor" ? "wait for terminal pane \(plain.dropFirst().joined(separator: " "))"
             : "read terminal pane \(plain.dropFirst().joined(separator: " "))"
    case "changed": line = "wait for the screen to change"
    case "dialog": line = plain.first == "dismiss" ? "clear any dialog in the way" : "check for a dialog"
    case "wait": line = "pause \(quoted)s"
    case "idle": line = "idle"
    default: line = "\(cmd) \(args.joined(separator: " "))"
    }

    var notes: [String] = []
    if let app = val("--require") { notes.append("only if \(app) is in front") }
    if args.contains("--expect-change") { notes.append("confirm the screen changed") }
    if let t = val("--expect") { notes.append("confirm \"\(t)\" appears") }
    if args.contains("--verify") { notes.append("read it back") }
    if let r = val("--retry") { notes.append("retry up to \(r)x") }
    if args.contains("--recover") { notes.append("clear anything in the way first") }
    if let t = val("--timeout") { notes.append("up to \(t)s") }
    return notes.isEmpty ? line : "\(line), \(notes.joined(separator: ", "))"
}

/// Runs an action and, when an expectation was given, proves it happened.
func executeChecked(_ cmd: String, _ rest: [String]) {
    var rest = rest
    var expectChange: CGRect?
    var expectText: String?
    var retries = 0
    var timeout = 4.0
    var recover = false

    // Pulled out before the action sees them, and kept for every retry.
    if let i = rest.firstIndex(of: "--expect-change") {
        let arg = i + 1 < rest.count ? rest[i + 1] : nil
        if let arg = arg, let region = parseRegion(arg) {
            expectChange = region
            rest.removeSubrange(i...(i + 1))
        } else {
            expectChange = frontWindowRect() ?? screen
            rest.remove(at: i)
        }
    }
    if let i = rest.firstIndex(of: "--expect"), i + 1 < rest.count {
        expectText = rest[i + 1]; rest.removeSubrange(i...(i + 1))
    }
    if let i = rest.firstIndex(of: "--retry"), i + 1 < rest.count {
        retries = Int(rest[i + 1]) ?? 0; rest.removeSubrange(i...(i + 1))
    }
    if let i = rest.firstIndex(of: "--expect-timeout"), i + 1 < rest.count {
        timeout = Double(rest[i + 1]) ?? 4; rest.removeSubrange(i...(i + 1))
    }
    if let i = rest.firstIndex(of: "--recover") { recover = true; rest.remove(at: i) }

    guard expectChange != nil || expectText != nil else { execute(cmd, rest); return }

    let app = rest.firstIndex(of: "--app").map { rest[$0 + 1] }
    for attempt in 0...retries {
        // Clear the way before acting, not only after failing. A sheet on top does not
        // block input, it absorbs it: keystrokes meant for the document land in the
        // save panel's filename field, and the screen changes, so the action even
        // looks like it worked.
        if recover, let blocking = frontDialog() {
            FileHandle.standardError.write(
                "human: '\(blocking.title)' is in the way, clearing it first\n".data(using: .utf8)!)
            execute("dialog", ["dismiss"])
            nap(Double.random(in: 0.4...0.9))
        }
        // Taken before the action, or it records the result and then waits for a change
        // that already happened. The tree is free, so it is always sampled; the pixel
        // baseline costs seconds and is only paid for when there is no tree.
        let axBefore = expectChange != nil ? axStateHash(app) : nil
        let before = (expectChange != nil && axBefore == nil) ? expectChange.flatMap { baseline($0) } : nil
        execute(cmd, rest)
        if verify(against: before, region: expectChange, expectText: expectText,
                  app: app, timeout: timeout, axBefore: axBefore) { return }
        if attempt < retries {
            FileHandle.standardError.write("human: no effect, trying again\n".data(using: .utf8)!)
            nap(Double.random(in: 0.4...1.1))      // a person pauses before repeating
        }
    }
    FileHandle.standardError.write("human: \(cmd) had no visible effect\n".data(using: .utf8)!)
    exit(8)
}

/// One command per line, # for comments. Quoted text stays a single argument.
func parseScript(_ body: String) -> [(String, [String])] {
    var steps: [(String, [String])] = []
    for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        var parts: [String] = []
        var current = ""
        var quoted = false
        for c in line {
            if c == "\"" { quoted.toggle(); continue }
            if c == " " && !quoted {
                if !current.isEmpty { parts.append(current); current = "" }
                continue
            }
            current.append(c)
        }
        if !current.isEmpty { parts.append(current) }
        guard let head = parts.first else { continue }
        steps.append((head, Array(parts.dropFirst())))
    }
    return steps
}

func loadScript(_ path: String) -> String {
    if path == "-" {
        return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

/// One step of work, with the pause a person would have taken before starting it.
func performStep(_ cmd: String, _ args: [String], checked: Bool = true) {
    transitionPause(from: session.lastVerb, to: cmd, since: gapBefore)
    gapBefore = 0
    if !offstage.contains(cmd) { session.lastVerb = cmd }
    if checked { executeChecked(cmd, args) } else { execute(cmd, args) }
}

/// How long the whole thing would take, measured by rehearsing it rather than guessing.
/// The rehearsal has to leave no trace, or planning a script would age the session that
/// then runs it.
func rehearse(_ steps: [(String, [String])]) -> Double {
    let wasDry = dry, wasGap = gapBefore, wasVerb = session.lastVerb
    dry = true
    dryElapsed = 0
    for (cmd, args) in steps { performStep(cmd, args, checked: false) }
    let total = dryElapsed
    dry = wasDry
    dryElapsed = 0
    gapBefore = wasGap
    session.lastVerb = wasVerb
    return total
}

func printPlan(_ steps: [(String, [String])], _ name: String) {
    print("\(name), \(steps.count) step\(steps.count == 1 ? "" : "s")")
    for (i, step) in steps.enumerated() {
        print(String(format: "  %2d. %@", i + 1, describe(step.0, step.1)))
    }
    let seconds = rehearse(steps)
    print(String(format: "  about %@ at a human pace",
                 seconds < 90 ? "\(Int(seconds.rounded()))s"
                              : String(format: "%.1f minutes", seconds / 60)))
}

if cmd == "plan" {
    let path = argv.first ?? "-"
    printPlan(parseScript(loadScript(path)), path == "-" ? "plan" : path)

} else if cmd == "run" {
    let verbose = takeFlag("--verbose")
    let confirm = takeFlag("--confirm")
    if takeFlag("--dry") { dry = true }
    let path = argv.first ?? "-"
    let steps = parseScript(loadScript(path))

    if confirm || dry {
        printPlan(steps, path == "-" ? "plan" : path)
    }
    if confirm && !dry {
        // Asked once, before anything happens, because the point of a plan is the
        // chance to say no.
        print("\nrun it? [y/N] ", terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard answer == "y" || answer == "yes" else { print("stopped, nothing was done"); exit(0) }
        print("")
    }

    var done = 0
    let began = Date()
    for (i, step) in steps.enumerated() {
        if !dry {
            FileHandle.standardError.write(
                "[\(i + 1)/\(steps.count)] \(describe(step.0, step.1))\n".data(using: .utf8)!)
        } else if verbose {
            FileHandle.standardError.write("  would: \(describe(step.0, step.1))\n".data(using: .utf8)!)
        }
        performStep(step.0, step.1)
        done += 1
    }

    if dry {
        print("rehearsal only, nothing was touched")
    } else {
        let took = Date().timeIntervalSince(began)
        FileHandle.standardError.write(
            String(format: "done: %d of %d steps in %.0fs\n", done, steps.count, took).data(using: .utf8)!)
    }

} else {
    performStep(cmd, argv)
}
