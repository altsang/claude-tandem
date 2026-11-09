// Handoffs and Macs: what is where, what is on its way, and the inbox.
//
// What it shows comes from `tandem where --json` (bin/tandem-ledger.py): every shared
// project's ownership events, intents and requests, merged with the presence card each
// Mac's Tandem publishes on the shared drive. What it does is `tandem send`, `tandem
// receive --defer`, `tandem settle` and `tandem ask`, run here with TANDEM_STEPS=1 so the
// window can show their steps — the CLI stays the one implementation of the mechanics.
//
// The ledger is read in the background whether or not the window is open: listing the
// shared folders is also what makes iCloud deliver to an idle Mac, and it is how a
// handoff addressed to this Mac becomes a notification.
import AppKit
import SwiftUI
import UserNotifications

// MARK: the ledger

struct Ledger: Decodable, Equatable {
    let schema: Int?
    let me: String
    let root: String
    let projects: [LProject]
    let machines: [Machine]
    let unshared: [Unshared]
    let inbox: [RawItem]
}

/// An inbox item as `tandem inbox --json` reports it — computed by the CLI, so the app,
/// `tandem watch` and scripts agree on what is waiting and on each item's key.
struct RawItem: Decodable, Equatable {
    let kind: String, key: String, project: String, side: String
    let profile: String?, other: String?, note: String?, at: String?, doc: String?, to: String?
}

struct LEvent: Decodable, Equatable {
    let verb: String?, machine: String?, to: String?, at: String?, note: String?, doc: String?, file: String?
}
struct LHist: Decodable, Equatable { let at: String, side: String, verb: String }
struct LDoc: Decodable, Equatable { let name: String, modified: String?, stale: Bool }
struct Intent: Decodable, Equatable { let to: String?, note: String?, doc: String?, file: String, at: String? }
struct Request: Decodable, Equatable { let from: String?, note: String?, file: String, at: String? }
struct Settle: Decodable, Equatable { let project: String, side: String, profile: String, needs: [String] }
struct Unshared: Decodable, Hashable { let project: String, side: String, mac: String, name: String? }

struct LProject: Decodable, Equatable, Identifiable {
    let name: String
    let holder: String?
    let state: String          // held · sent · unrecorded · unreadable
    let last: LEvent?
    let history: [LHist]
    let doc: LDoc?
    let intents: [Intent]
    let requests: [Request]
    let settling: [Settle]
    var id: String { name }
}

struct Drive: Decodable, Equatable {
    let state: String?, lastSync: String?, minutes: Int?, stalled: Bool?
    enum CodingKeys: String, CodingKey { case state, minutes, stalled, lastSync = "last_sync" }
}

struct MSide: Decodable, Equatable, Identifiable {
    let side: String
    let profile: String?, name: String?, email: String?, plan: String?, open: Bool?, color: String?
    let projects: [String]?
    let held: [String]?        // this Mac only: projects this profile locked itself out of (--hold)
    var id: String { side }
}

struct Machine: Decodable, Equatable, Identifiable {
    let mac: String
    let this: Bool?
    let silent: Bool?
    let ageMinutes: Int?
    let version: String?
    let drive: Drive?
    let sides: [MSide]
    var id: String { mac }
    enum CodingKeys: String, CodingKey { case mac, this, silent, version, drive, sides, ageMinutes = "age_minutes" }
    /// A card refreshed every few minutes: older than a quarter of an hour, the Mac is asleep or off.
    var online: Bool { this == true || (ageMinutes ?? 9999) < 15 }
}

func tsDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    for fmt in ["yyyyMMdd'T'HHmmss'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
        f.dateFormat = fmt
        if let d = f.date(from: s) { return d }
    }
    return nil
}

func ago(_ s: String?) -> String {
    guard let d = tsDate(s) else { return "" }
    if Date().timeIntervalSince(d) < 60 { return "just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: d, relativeTo: Date())
}

func agoMinutes(_ m: Int?) -> String {
    guard let m else { return "never" }
    if m < 1 { return "just now" }
    if m < 60 { return "\(m) min ago" }
    if m < 60 * 48 { return "\(m / 60) h ago" }
    return "\(m / 1440) days ago"
}

// MARK: the inbox

enum InboxKind: String { case arrival, brief, request, settling, delivered }

struct InboxItem: Identifiable {
    let kind: InboxKind
    let project: LProject
    let side: String        // the side on this Mac it concerns
    let other: String?      // who sent it, where it's going, or who asks
    let note: String?
    let at: String?
    let key: String         // stable: what has already been announced
    var to: String? = nil   // a brief's destination, resolved by the CLI; nil when it names nobody known
    var doc: String? = nil
    var id: String { key }
}

// MARK: a running step: send, receive, settle, sync, doctor

struct StepState: Equatable { var state: String; var detail: String }

final class Job: ObservableObject, Identifiable {
    let id = UUID()
    let kind: String
    let title: String
    let project: String?
    let side: String?
    let order: [String]
    let started = Date()
    @Published var steps: [String: StepState] = [:]
    @Published var log = ""
    @Published var progress = ""
    @Published var running = true
    @Published var code: Int32 = 0
    @Published var finished: Date?

    init(kind: String, title: String, project: String? = nil, side: String? = nil) {
        self.kind = kind; self.title = title; self.project = project; self.side = side
        switch kind {
        case "send": order = ["brief", "prepare", "event", "upload"]
        case "receive": order = ["event", "files", "define", "claim", "memory", "unlock", "brief"]
        case "settle": order = ["define", "memory", "unlock"]
        default: order = []
        }
    }

    var ok: Bool { !running && code == 0 }
    var waitingOnQuit: Bool { steps.values.contains { $0.state == "wait" } && ok }

    static let labels: [String: String] = [
        "brief": "Brief", "prepare": "Files ready, manifest and memory snapshot", "event": "Ownership event",
        "upload": "Uploaded to the drive", "files": "Every file verified (md5)", "define": "Project defined here",
        "claim": "Claimed", "memory": "Memory merged", "unlock": "Lock lifted",
    ]
}

extension Store {
    /// The sides on this Mac, from the profiles: "Madoka", "Madoka@work".
    var mySides: [String] { profiles.map { app?.side($0) ?? $0.id } }
    func profile(forSide s: String) -> Profile? { profiles.first { app?.side($0) == s } }
    func isMine(_ side: String?) -> Bool { side.map { mySides.contains($0) } ?? false }
    func label(_ side: String) -> String {
        if let p = profile(forSide: side) { return "\(p.name) on this Mac" }
        for m in ledger?.machines ?? [] {
            if let s = m.sides.first(where: { $0.side == side }), let n = s.name { return "\(n) on \(m.mac)" }
        }
        return side
    }

    /// What's waiting, as the CLI computed it (`tandem inbox`), joined to its project.
    var allInbox: [InboxItem] {
        guard let l = ledger else { return [] }
        return l.inbox.compactMap { r in
            guard let kind = InboxKind(rawValue: r.kind), let p = l.projects.first(where: { $0.name == r.project }) else { return nil }
            return InboxItem(kind: kind, project: p, side: r.side, other: r.other, note: r.note, at: r.at, key: r.key,
                             to: r.to, doc: r.doc)
        }
    }
    var inbox: [InboxItem] { allInbox.filter { $0.kind != .delivered } }

    /// What this Mac sent that the other side hasn't claimed yet.
    var outgoing: [LProject] {   // not those going to another profile here: they're in the inbox
        (ledger?.projects ?? []).filter { $0.state == "sent" && isMine($0.last?.machine) && !isMine($0.holder) }
    }

    func sidesDefining(_ project: String) -> [String] {
        let me = ledger?.machines.first { $0.this == true }
        return me?.sides.filter { $0.projects?.contains(project) ?? false }.map(\.side) ?? []
    }

    /// Every side a project can go to: this Mac's other profiles, and every side seen on the other Macs.
    func targets(from: String) -> [String] {
        var all = mySides
        for m in ledger?.machines ?? [] where m.this != true { all += m.sides.map(\.side) }
        var seen = Set<String>()
        return all.filter { $0 != from && seen.insert($0).inserted }
    }

    // MARK: reading the ledger

    func refreshLedger() {
        guard !ledgerLoading, let app else { return }
        ledgerLoading = true
        let tandem = app.tandem, path = app.path
        DispatchQueue.global(qos: .utility).async {
            let r = runProcess("/bin/bash", [tandem, "where", "--json"], path: path)
            let l = r.code == 0 ? (try? JSONDecoder().decode(Ledger.self, from: Data(r.out.utf8))) : nil
            DispatchQueue.main.async {
                self.ledgerLoading = false
                guard let l else { return }
                self.ledgerAt = Date()
                if l != self.ledger { self.ledger = l }
                self.react()
                app.updateStatusIcon()
            }
        }
    }

    /// Always on: every minute, or every 10 s while the window is open. Presence every 5 min.
    func startLedger() {
        loadConfig()
        refreshLedger()
        publishPresence()
        ledgerTimer?.invalidate()
        ledgerTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ledgerTicks += 1
            if self.windowOpen || self.ledgerTicks % 6 == 0 { self.refreshLedger(); self.loadConfig() }
            if self.ledgerTicks % 30 == 0 { self.publishPresence() }
        }
    }

    func publishPresence() {
        guard let app else { return }
        let tandem = app.tandem, path = app.path
        DispatchQueue.global(qos: .utility).async { _ = runProcess("/bin/bash", [tandem, "presence"], path: path) }
    }

    // MARK: reacting — notifications and the automatic parts

    private func recent(_ at: String?, days: Double = 3) -> Bool {
        guard let d = tsDate(at) else { return true }
        return Date().timeIntervalSince(d) < days * 86400
    }

    func react() {
        let d = UserDefaults.standard
        var seen = d.stringArray(forKey: "notified") ?? []
        let onArrival = config["on-arrival"] ?? "ask"
        let onBrief = config["on-brief"] ?? "ask"
        for item in allInbox where !seen.contains(item.key) && recent(item.at, days: item.kind == .delivered ? 1 : 3) {
            seen.append(item.key)
            let p = item.project
            switch item.kind {
            case .arrival:
                let from = item.other.map(label) ?? "the other side"
                if onArrival == "auto" {
                    startReceive(p.name, as: item.side)
                } else if onArrival == "ask" {
                    notifier.post(id: item.key, title: "\(p.name) arrived from \(from)",
                                  body: "For \(label(item.side))" + (item.note.map { $0.isEmpty ? "" : " · \($0)" } ?? ""),
                                  category: "ARRIVAL", info: ["project": p.name, "side": item.side])
                }
            case .brief:
                let to = item.to
                if onBrief == "auto", let to {
                    startSend(SendDraft(project: p.name, from: item.side, to: to, note: item.note ?? "",
                                        doc: item.doc ?? p.doc?.name, noDoc: false, hold: false))
                } else {
                    notifier.post(id: item.key, title: "Send \(p.name) to \(to.map(label) ?? item.other ?? "…")?",
                                  body: "/handoff wrote \(p.intents.last?.doc ?? p.doc?.name ?? "a brief")" + (item.note.map { $0.isEmpty ? "" : " · \($0)" } ?? ""),
                                  category: "BRIEF", info: ["project": p.name, "side": item.side, "key": item.key])
                }
            case .request:
                notifier.post(id: item.key, title: "\(item.other.map(label) ?? "The other Mac") asks for \(p.name)",
                              body: "Run /handoff in its Claude session, then send it — or send it without a brief.",
                              category: "REQUEST", info: ["project": p.name, "side": item.side, "to": item.other ?? ""])
            case .delivered:
                notifier.post(id: item.key, title: "\(p.name) was received",
                              body: "\(label(item.other ?? "")) verified every file and holds it now.", category: "INFO", info: [:])
            case .settling:
                break
            }
        }
        d.set(Array(seen.suffix(400)), forKey: "notified")

        // A receive's paused steps are finished by a settle — this app's, `tandem watch`'s or
        // one run by hand. Once nothing for that project is left settling, show them done.
        let settling = Set(inbox.filter { $0.kind == .settling }.map { "\($0.project.name)|\($0.side)" })
        for job in jobs where job.kind == "receive" && job.waitingOnQuit {
            guard let p = job.project, let s = job.side, !settling.contains("\(p)|\(s)"),
                  !self.jobs.contains(where: { $0.running && $0.kind == "settle" && $0.project == p }) else { continue }
            for (k, v) in job.steps where v.state == "wait" { job.steps[k] = StepState(state: "done", detail: "") }
        }

        // a deferred receive finishes as soon as its profile's Claude is closed
        for item in inbox where item.kind == .settling {
            guard let pr = profile(forSide: item.side), !pr.open,
                  !jobs.contains(where: { $0.running && $0.kind == "settle" && $0.side == item.side }) else { continue }
            startSettle(item.project.name, as: item.side)
        }
    }

    // MARK: doing

    func profileArgs(_ side: String) -> [String] {
        guard let p = profile(forSide: side), !p.isDefault else { return [] }
        return ["--profile", p.id]
    }

    @discardableResult
    func run(_ job: Job, _ args: [String], then: ((Job) -> Void)? = nil) -> Job {
        guard let app else { return job }
        jobs.insert(job, at: 0)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [app.tandem] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = app.path
        env["TANDEM_STEPS"] = "1"
        env["TANDEM_NO_CLIPBOARD"] = "1"   // the brief goes on the clipboard when you open Claude, not before
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            buffer += String(decoding: data, as: UTF8.self)
            var lines: [String] = []
            while let r = buffer.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n")) {
                lines.append(String(buffer[..<r.lowerBound]))
                buffer = String(buffer[r.upperBound...])
            }
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                for line in lines where !line.isEmpty {
                    if line.hasPrefix("::step::") {
                        let parts = line.components(separatedBy: "::")   // "", "step", name, state, detail
                        if parts.count >= 4 {
                            job.steps[parts[2]] = StepState(state: parts[3], detail: parts.count > 4 ? parts[4] : "")
                        }
                    } else if line.contains("░") || line.contains("█") || line.range(of: #"^\s*\d+s$"#, options: .regularExpression) != nil {
                        job.progress = line.trimmingCharacters(in: .whitespaces)
                    } else {
                        job.log += line + "\n"
                    }
                }
            }
        }
        p.terminationHandler = { proc in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                job.running = false
                job.code = proc.terminationStatus
                job.finished = Date()
                job.progress = ""
                // 75: another client (tandem watch, a script) is already doing exactly this
                if job.code == 75 { self.jobs.removeAll { $0.id == job.id }; self.refreshLedger(); return }
                then?(job)
                self.refresh()
                self.refreshLedger()
                self.objectWillChange.send()
            }
        }
        do { try p.run() } catch {
            job.log += "\(error)\n"; job.running = false; job.code = 127
        }
        return job
    }

    func running(_ kind: String, _ project: String?) -> Bool {
        jobs.contains { $0.running && $0.kind == kind && $0.project == project }
    }

    func startReceive(_ project: String, as side: String) {
        guard !running("receive", project) else { return }
        run(Job(kind: "receive", title: "Receive \(project) as \(label(side))", project: project, side: side),
            profileArgs(side) + ["receive", project, "--defer", "--timeout", "900"]) { job in
            if job.ok {
                let later = job.waitingOnQuit
                self.notifier.post(id: "recv:\(project):\(job.id)", title: "\(project) is here",
                                   body: later ? "Verified and claimed. It finishes setting up when Claude (\(self.profile(forSide: side)?.name ?? side)) quits."
                                               : "Verified and claimed. Open it in Claude — the brief goes on the clipboard.",
                                   category: "RECEIVED", info: ["project": project, "side": side])
            } else {
                self.notifier.post(id: "recvfail:\(project):\(job.id)", title: "\(project) didn’t arrive",
                                   body: job.log.split(separator: "\n").first { $0.hasPrefix("error") }.map(String.init) ?? "See Claude Tandem › Handoffs.",
                                   category: "INFO", info: [:])
            }
        }
    }

    func startSend(_ d: SendDraft) {
        guard !running("send", d.project) else { return }
        var args = profileArgs(d.from) + ["send", d.project, "--to", d.to]
        if !d.note.isEmpty { args += ["--note", d.note] }
        if d.noDoc { args.append("--no-doc") } else if let doc = d.doc { args += ["--doc", doc] }
        if d.hold { args.append("--hold") }
        run(Job(kind: "send", title: "Hand off \(d.project) → \(label(d.to))", project: d.project, side: d.from), args) { job in
            self.notifier.post(id: "sent:\(d.project):\(job.id)",
                               title: job.ok ? "\(d.project) is on its way to \(self.label(d.to))" : "\(d.project) wasn’t sent",
                               body: job.ok ? "Every file is uploaded. You’ll hear when it’s received."
                                            : (job.log.split(separator: "\n").first { $0.hasPrefix("error") }.map(String.init) ?? "See Claude Tandem › Handoffs."),
                               category: "INFO", info: [:])
        }
    }

    func startSettle(_ project: String, as side: String) {
        run(Job(kind: "settle", title: "Finish setting up \(project) for \(label(side))", project: project, side: side),
            profileArgs(side) + ["settle", project])
    }

    func quitAndFinish(_ project: String, as side: String) {
        guard let p = profile(forSide: side) else { return }
        app?.cli(["quit", p.id]) { self.startSettle(project, as: side) }
    }

    func ask(_ project: String, as side: String) {
        run(Job(kind: "ask", title: "Ask for \(project) as \(label(side))", project: project, side: side),
            profileArgs(side) + ["ask", project])
    }

    /// A step whose output is the point — doctor, check, a project's history — shown in a sheet.
    /// A CLI step whose output is shown in a sheet — over the Settings window when it was
    /// started there, else over the main window.
    func runLog(_ title: String, _ args: [String], inSettings: Bool = false) {
        let job = Job(kind: "log", title: title)
        if inSettings { settingsLogJob = job } else { logJob = job }
        run(job, args)
    }

    func loadConfig() {
        guard let app else { return }
        let tandem = app.tandem, path = app.path
        DispatchQueue.global(qos: .utility).async {
            let r = runProcess("/bin/bash", [tandem, "config", "--json"], path: path)
            let d = (try? JSONSerialization.jsonObject(with: Data(r.out.utf8))) as? [String: Any] ?? [:]
            let c = d.compactMapValues { $0 as? String }
            DispatchQueue.main.async { if c != self.config { self.config = c } }
        }
    }

    func setConfig(_ key: String, _ value: String) {
        config[key] = value
        guard let app else { return }
        let tandem = app.tandem, path = app.path
        DispatchQueue.global(qos: .userInitiated).async {
            let r = runProcess("/bin/bash", [tandem, "config", "set", key, value], path: path)
            DispatchQueue.main.async { if r.code != 0 { app.alert("Couldn’t change that setting", r.err) }; self.loadConfig() }
        }
    }

    /// Projects a profile here has locked itself out of with --hold.
    func heldHere(_ side: String) -> [String] {
        ledger?.machines.first { $0.this == true }?.sides.first { $0.side == side }?.held ?? []
    }

    /// The brief on the clipboard (`tandem brief --copy`), and the profile's Claude in front.
    func openInClaude(_ project: String, as side: String) {
        guard let app else { return }
        let tandem = app.tandem, path = app.path, args = profileArgs(side) + ["brief", project, "--copy"]
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runProcess("/bin/bash", [tandem] + args, path: path)
            DispatchQueue.main.async { if let p = self.profile(forSide: side) { app.openDesktop(p) } }
        }
    }

    func dismiss(_ key: String) {
        guard let app else { return }
        let tandem = app.tandem, path = app.path
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runProcess("/bin/bash", [tandem, "inbox", "dismiss", key], path: path)
            DispatchQueue.main.async { self.refreshLedger() }
        }
    }

    func draft(_ project: String, from side: String, to: String? = nil) {
        let p = ledger?.projects.first { $0.name == project }
        let intent = p?.intents.last
        let brief = inbox.last { $0.kind == .brief && $0.project.name == project }
        sendDraft = SendDraft(project: project, from: side, to: to ?? brief?.to ?? "",
                              note: intent?.note ?? "", doc: intent?.doc ?? p?.doc?.name, noDoc: p?.doc == nil, hold: false)
    }

    func showInFinder(_ project: String) {
        guard let root = ledger?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "\(root)/Projects/\(project)")])
    }
}

// MARK: notifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    weak var store: Store?
    var allowed = false

    func setup() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let open = UNNotificationAction(identifier: "SHOW", title: "Show", options: [.foreground])
        c.setNotificationCategories([
            UNNotificationCategory(identifier: "ARRIVAL", actions: [
                UNNotificationAction(identifier: "RECEIVE", title: "Receive", options: []), open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "BRIEF", actions: [
                UNNotificationAction(identifier: "SEND", title: "Send…", options: [.foreground])], intentIdentifiers: []),
            UNNotificationCategory(identifier: "REQUEST", actions: [
                UNNotificationAction(identifier: "COPY", title: "Copy /handoff", options: []),
                UNNotificationAction(identifier: "SEND", title: "Send…", options: [.foreground])], intentIdentifiers: []),
            UNNotificationCategory(identifier: "RECEIVED", actions: [
                UNNotificationAction(identifier: "OPEN", title: "Open in Claude", options: [.foreground])], intentIdentifiers: []),
            UNNotificationCategory(identifier: "INFO", actions: [], intentIdentifiers: []),
        ])
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in DispatchQueue.main.async { self.allowed = ok } }
    }

    func post(id: String, title: String, body: String, category: String, info: [String: String]) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.categoryIdentifier = category
        c.userInfo = info
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = r.notification.request.content.userInfo as? [String: String] ?? [:]
        let project = info["project"] ?? "", side = info["side"] ?? ""
        DispatchQueue.main.async {
            guard let store = self.store else { return }
            switch r.actionIdentifier {
            case "RECEIVE": store.startReceive(project, as: side)
            case "OPEN": store.openInClaude(project, as: side)
            case "COPY":
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("/handoff to \(info["to"] ?? "the other Mac")", forType: .string)
            case "SEND":
                store.app?.showWindow(select: "handoffs")
                store.draft(project, from: side, to: info["to"].flatMap { $0.isEmpty ? nil : $0 })
            default:
                store.app?.showWindow(select: "handoffs")
            }
            done()
        }
    }
}

// MARK: views — Handoffs

struct HandoffsView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Waiting for you") { waiting.padding(6) }
                if store.jobs.contains(where: { ["send", "receive", "settle", "ask"].contains($0.kind) }) || !store.outgoing.isEmpty {
                    GroupBox("In progress") { inProgress.frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)   // the scroll view spans the page, not just the column
        }
        .navigationSubtitle(subtitle)
        .toolbar { ToolbarItem(placement: .primaryAction) { CheckNowButton(store: store) } }
    }

    /// "1 waiting", in the title bar.
    var subtitle: String {
        guard store.ledger != nil else { return "Reading the shared drive…" }
        let n = store.inbox.filter { $0.kind != .settling }.count
        return n == 0 ? "Nothing waiting" : "\(n) waiting"
    }

    @ViewBuilder var waiting: some View {
        let items = store.inbox
        if items.isEmpty {
            Text(store.ledger == nil ? "Reading the shared drive…" : "Nothing waiting.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    InboxRow(store: store, item: item)
                    if item.id != items.last?.id { Divider() }
                }
            }
        }
    }

    var inProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            let jobs = Array(store.jobs.filter { ["send", "receive", "settle", "ask"].contains($0.kind) }.prefix(6))
            ForEach(jobs) { job in
                JobRow(store: store, job: job)
                if job.id != jobs.last?.id || !store.outgoing.isEmpty { Divider() }
            }
            ForEach(store.outgoing) { p in
                HStack(alignment: .top) {
                    Image(systemName: "paperplane").foregroundStyle(.blue).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).fontWeight(.semibold)
                        let old = tsDate(p.last?.at).map { Date().timeIntervalSince($0) > 2 * 86400 } ?? false
                        Text("Sent to \(store.label(p.holder ?? "")) \(ago(p.last?.at)) — " + (old
                             ? "never received there. If it was worked on over there without a receive, run tandem receive on that Mac to record it."
                             : "waiting for it to be received there"))
                            .font(.callout).foregroundStyle(old ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
                        if let m = otherMac(p.holder), !m.online {
                            Text(m.silent == true ? "\(m.mac) doesn’t publish its status, so Tandem can’t tell whether it’s awake."
                                                  : "\(m.mac) was last seen \(agoMinutes(m.ageMinutes)) — it lands when it wakes.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    func otherMac(_ side: String?) -> Machine? {
        guard let mac = side?.split(separator: "@").first.map(String.init) else { return nil }
        return store.ledger?.machines.first { $0.mac == mac }
    }
}

struct InboxRow: View {
    @ObservedObject var store: Store
    let item: InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let n = item.note, !n.isEmpty, item.kind != .settling {
                    Text("“\(n)”").font(.callout).italic().fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            buttons
        }
    }

    var icon: String {
        switch item.kind {
        case .arrival: return "arrow.down.circle.fill"
        case .brief: return "arrow.up.circle.fill"
        case .request: return "hand.raised.circle.fill"
        case .settling: return "pause.circle.fill"
        case .delivered: return "checkmark.circle.fill"
        }
    }
    var color: Color {
        switch item.kind {
        case .arrival: return .green
        case .brief: return .blue
        case .request: return .purple
        case .settling: return .orange
        case .delivered: return .green
        }
    }
    var title: String {
        let p = item.project.name
        switch item.kind {
        case .arrival: return "\(p) — from \(store.label(item.other ?? "?"))"
        case .brief: return "\(p) — brief ready to send"
        case .request: return "\(store.label(item.other ?? "?")) asks for \(p)"
        case .settling: return "\(p) — almost done"
        case .delivered: return "\(p) — received by \(store.label(item.other ?? "?"))"
        }
    }
    var subtitle: String {
        switch item.kind {
        case .arrival:
            return "For \(store.label(item.side)) · sent \(ago(item.at))" + (item.project.last?.doc.map { $0.isEmpty ? "" : " · brief \($0)" } ?? "")
        case .brief:
            let to = item.to.map(store.label) ?? item.other.map { "“\($0)” (pick who it goes to)" } ?? "—"
            return "/handoff wrote \(item.doc ?? item.project.doc?.name ?? "a brief") \(ago(item.at)) · to \(to)"
        case .request:
            return "\(store.label(item.side)) holds it · asked \(ago(item.at)). Run /handoff in its Claude session, then send it."
        case .settling:
            let name = store.profile(forSide: item.side)?.name ?? item.side
            return "Received and claimed. Still to do for \(name) once its Claude quits: \(item.note ?? "")."
        case .delivered:
            return "Received \(ago(item.at))"
        }
    }

    @ViewBuilder var buttons: some View {
        let p = item.project.name
        switch item.kind {
        case .arrival:
            Button("Receive") { store.startReceive(p, as: item.side) }
                .disabled(store.running("receive", p)).keyboardShortcut(.defaultAction)
        case .brief:
            HStack {
                Button("Not Now") { store.dismiss(item.key) }
                Button("Send…") { store.draft(p, from: item.side) }
            }
        case .request:
            HStack {
                Button("Copy /handoff") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("/handoff to \(item.other ?? "")", forType: .string)
                }
                Button("Send…") { store.draft(p, from: item.side, to: item.other) }
            }
        case .settling:
            let open = store.profile(forSide: item.side)?.open ?? false
            if open {
                Button("Quit Claude and Finish") { store.quitAndFinish(p, as: item.side) }
            } else {
                Button("Finish Now") { store.startSettle(p, as: item.side) }.disabled(store.running("settle", p))
            }
        case .delivered:
            EmptyView()
        }
    }
}

struct JobRow: View {
    @ObservedObject var store: Store
    @ObservedObject var job: Job
    @ViewState private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if job.running { ProgressView().controlSize(.small) }
                else { Image(systemName: job.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(job.ok ? .green : .red) }
                Text(job.title).fontWeight(.semibold)
                Spacer()
                if job.ok, job.kind == "receive", let p = job.project, let s = job.side {
                    Button("Open in Claude") { store.openInClaude(p, as: s) }
                        .help("Puts the brief on the clipboard and brings this profile’s Claude forward — paste it into the project’s Claude session")
                }
                if !job.running { Button { store.jobs.removeAll { $0.id == job.id } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless) }
            }
            ForEach(job.order.filter { job.steps[$0] != nil }, id: \.self) { name in
                let s = job.steps[name]!
                HStack(spacing: 6) {
                    Image(systemName: symbol(s.state)).foregroundStyle(tint(s.state)).frame(width: 16)
                    Text(Job.labels[name] ?? name)
                    Text(detail(name, s)).foregroundStyle(.secondary)
                }.font(.callout)
            }
            if !job.progress.isEmpty { Text(job.progress).font(.caption.monospaced()).foregroundStyle(.secondary) }
            if !job.running && !job.ok, let e = job.log.split(separator: "\n").first(where: { $0.hasPrefix("error") }) {
                Text(String(e)).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Details", isExpanded: $showLog) {
                Text(job.log.isEmpty ? "…" : job.log).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption)
        }
    }

    func symbol(_ s: String) -> String {
        switch s {
        case "done": return "checkmark.circle.fill"
        case "fail": return "xmark.circle.fill"
        case "wait": return "pause.circle"
        case "skip": return "minus.circle"
        default: return "circle.dotted"
        }
    }
    func tint(_ s: String) -> Color {
        switch s { case "done": return .green; case "fail": return .red; case "wait": return .orange; default: return .secondary }
    }
    func detail(_ name: String, _ s: StepState) -> String {
        if s.state == "wait" && ["define", "memory", "unlock"].contains(name) { return "— when Claude quits" }
        if s.state == "wait" && name == "event" { return "— waiting for it to arrive" }
        if s.state == "skip" { return !s.detail.isEmpty ? "— \(s.detail)" : (name == "brief" ? "— none" : "— not needed") }
        return s.detail.isEmpty ? "" : "— \(s.detail)"
    }
}

// MARK: views — Macs

struct MacsView: View {
    @ObservedObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 4) {
                    Text("Each Mac running Tandem publishes a card every few minutes.").foregroundStyle(.secondary)
                    InfoButton(text: "A card holds the Mac’s profiles, their accounts, and what each one holds. It travels on the shared drive, so it is 1–3 minutes old at best. A Mac whose newest card hasn’t downloaded yet keeps showing its last one.")
                }
                if let l = store.ledger {
                    ForEach(l.machines) { m in MacCard(store: store, m: m) }
                } else {
                    ProgressView()
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationSubtitle(subtitle)
        .toolbar { ToolbarItem(placement: .primaryAction) { CheckNowButton(store: store) } }
    }

    var subtitle: String {
        guard let l = store.ledger else { return "Reading the shared drive…" }
        let others = l.machines.filter { $0.this != true }
        let up = others.filter { $0.online }.count
        return others.isEmpty ? "This Mac only" : "\(l.machines.count) Macs · \(up + 1) online"
    }
}

/// Re-reads the shared drive now (⌘R in the Handoffs menu).
struct CheckNowButton: View {
    @ObservedObject var store: Store
    var body: some View {
        Button { store.refreshLedger() } label: { Label("Check Now", systemImage: "arrow.clockwise") }
            .help(store.ledgerAt.map { "Check the shared drive now (⌘R) — last checked \(agoMinutes(Int(Date().timeIntervalSince($0) / 60)))" } ?? "Check the shared drive now (⌘R)")
    }
}

struct MacCard: View {
    @ObservedObject var store: Store
    let m: Machine

    var myVersion: String { store.ledger?.machines.first { $0.this == true }?.version ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: m.this == true ? "desktopcomputer" : "laptopcomputer").font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.mac).font(.title2.bold())
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(dot).frame(width: 10, height: 10)
                }
                if m.silent == true {
                    Text("\(m.mac) is known from handoffs, but its Tandem doesn’t publish a card — it’s older, or the app isn’t running there. On \(m.mac): brew upgrade claude-tandem && tandem menubar, then open Claude Tandem.")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                facts
                Divider()
                ForEach(m.sides) { s in side(s) }
            }.padding(6)
        }
    }

    var status: String {
        if m.this == true { return "This Mac" }
        if m.silent == true { return "No card" }
        return m.online ? "Online · seen \(agoMinutes(m.ageMinutes))" : "Asleep or off · last seen \(agoMinutes(m.ageMinutes))"
    }
    var dot: Color { m.this == true || m.online ? .green : (m.silent == true ? .gray : .orange) }

    @ViewBuilder var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            if let v = m.version {
                GridRow {
                    Text("Tandem").foregroundStyle(.secondary)
                    if m.this != true, !myVersion.isEmpty, v.compare(myVersion, options: .numeric) == .orderedAscending {
                        Text("\(v) — older than this Mac’s \(myVersion). Update it there: brew upgrade claude-tandem && tandem menubar").foregroundStyle(.orange)
                    } else { Text(v) }
                }
            }
            if let d = m.drive {
                GridRow {
                    Text("iCloud Drive").foregroundStyle(.secondary)
                    HStack {
                        if d.stalled == true {
                            Text("Stalled — \(d.state ?? "?"), last synced \(d.lastSync ?? "?"). Opening iCloud Drive in Finder restarts it.").foregroundStyle(.orange)
                            if m.this == true {
                                Button("Open iCloud Drive") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"))
                                }
                            }
                        } else {
                            Text(d.state == "idle" ? "In sync" : (d.state ?? "?"))
                        }
                    }
                }
            }
        }
        .font(.callout)
    }

    func side(_ s: MSide) -> some View {
        let holds = (store.ledger?.projects ?? []).filter { $0.holder == s.side }
        let coming = holds.filter { $0.state == "sent" }
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(nsColor: NSColor(hex: s.color ?? "#8A8A8E"))).frame(width: 14, height: 14).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(s.name ?? s.side).fontWeight(.semibold)
                    Text(s.side).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if s.open == true { Text("Claude open").font(.caption).foregroundStyle(.green) }
                }
                if let e = s.email { Text([e, s.plan?.capitalized].compactMap { $0 }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
                let held = holds.filter { $0.state == "held" }.map(\.name)
                Text(held.isEmpty ? "Holds no shared project" : "Holds " + held.joined(separator: ", "))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                if !coming.isEmpty {
                    Text("On its way here: " + coming.map(\.name).joined(separator: ", ")).font(.callout).foregroundStyle(.blue)
                }
                if let n = s.projects?.count, n > 0 {
                    Text("\(n) project\(n == 1 ? "" : "s") defined in its Claude").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: views — sending

struct SendDraft: Identifiable, Equatable {
    var project: String
    var from: String
    var to: String
    var note: String
    var doc: String?
    var noDoc: Bool
    var hold: Bool
    var id: String { project + "→" + from }
}

struct SendSheet: View {
    @ObservedObject var store: Store
    @ViewState var draft: SendDraft
    @Environment(\.dismiss) private var dismiss

    var p: LProject? { store.ledger?.projects.first { $0.name == draft.project } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hand off \(draft.project)").font(.title2.bold())
            Form {
                LabeledContent("From") { Text(store.label(draft.from)) }
                Picker("To", selection: $draft.to) {
                    if draft.to.isEmpty { Text("Choose…").tag("") }
                    ForEach(store.targets(from: draft.from), id: \.self) { t in Text(targetLabel(t)).tag(t) }
                }
                LabeledContent("Brief") { brief }
                TextField("Note", text: $draft.note, prompt: Text("one line: where it stands"))
                Toggle("Lock this Mac out of it until it comes back", isOn: $draft.hold)
                if draft.hold && (store.profile(forSide: draft.from)?.open ?? false) {
                    Text("Claude is open, so the lock can’t be written now; the send tells you the one command to run after you quit it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let m = targetMac, !m.online {
                Label(m.silent == true ? "\(m.mac) doesn’t publish its status — it receives when someone runs receive there."
                                       : "\(m.mac) was last seen \(agoMinutes(m.ageMinutes)). It’s sent now, and lands when \(m.mac) wakes.",
                      systemImage: "moon.zzz").font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send") {
                    store.startSend(draft)
                    for i in p?.intents ?? [] { store.dismiss("intent:\(draft.project)/\(i.file)") }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.to.isEmpty || (draft.doc == nil && !draft.noDoc))
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    var targetMac: Machine? {
        let mac = draft.to.split(separator: "@").first.map(String.init)
        return store.ledger?.machines.first { $0.mac == mac && $0.this != true }
    }

    func targetLabel(_ t: String) -> String {
        let mac = t.split(separator: "@").first.map(String.init) ?? t
        let m = store.ledger?.machines.first { $0.mac == mac }
        let state = m?.this == true ? "" : (m?.silent == true ? " · status unknown" : (m?.online == true ? " · online" : " · asleep"))
        let email = m?.sides.first { $0.side == t }?.email.map { " (\($0))" } ?? ""
        return store.label(t) + email + state
    }

    @ViewBuilder var brief: some View {
        if let d = draft.doc ?? p?.doc?.name, !draft.noDoc {
            VStack(alignment: .trailing, spacing: 2) {
                HStack {
                    Text(d)
                    Button("Open") {
                        if let root = store.ledger?.root { NSWorkspace.shared.open(URL(fileURLWithPath: "\(root)/Projects/\(draft.project)/\(d)")) }
                    }.controlSize(.small)
                }
                if p?.doc?.name == d, let m = p?.doc?.modified { Text("written \(ago(m))").font(.caption).foregroundStyle(.secondary) }
                if p?.doc?.name == d, p?.doc?.stale == true {
                    Text("Older than the last handoff — run /handoff again?").font(.caption).foregroundStyle(.orange)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                Text(p?.doc == nil ? "None — run /handoff in its Claude session" : "None").foregroundStyle(.orange)
                Toggle("Send without one", isOn: $draft.noDoc).toggleStyle(.checkbox)
            }
        }
    }
}
