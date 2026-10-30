// Claude Tandem — a menu-bar front end for bin/tandem (and its `tandem profile` half).
//
// Every action is a call to `tandem`, so the CLI stays the single
// implementation and this file only draws the menu and asks questions. Steps that take
// a while or talk back (handoffs, receive, doctor, sync, Claude Code) open in Terminal
// so their output is visible; quick ones (rename, badge, colour, quit) run here and
// report failures in an alert.
//
// Built by `tandem menubar`, which writes the script path and the user's PATH
// into Info.plist: an app started at login gets only /usr/bin:/bin.
//
// `ClaudeTandem --dump-menu <dir>` builds the menu without showing it, prints its
// tree and writes the icons it would draw into <dir>; the build checks itself with it.
import AppKit
import ServiceManagement

struct Profile: Decodable {
    let id: String
    let name: String
    let isDefault: Bool
    let email: String?
    let plan: String?
    let open: Bool
    let pid: Int32?
    let stale: Bool
    let color: String
    let badge: String
    let badgeImage: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, plan, open, pid, stale, color, badge
        case isDefault = "default", badgeImage = "badge_image"
    }
}

// tandem profile's default_color palette, offered as the colour choices
let palette: [(String, String)] = [("Blue", "#2F6FEB"), ("Green", "#1F9D55"), ("Purple", "#8E44AD"),
    ("Orange", "#D9480F"), ("Teal", "#0E9AA7"), ("Raspberry", "#C2255C"), ("Periwinkle", "#5C7CFA"),
    ("Ochre", "#B7791F"), ("Graphite", "#3A3A40")]

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Runs a program to completion; stdout and stderr kept apart so JSON stays parseable.
func runProcess(_ exe: String, _ args: [String], path: String) -> (code: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = path
    p.environment = env
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (127, "", "\(error)") }
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
}

/// NSMenuItem's target is weak; the item keeps this alive through representedObject.
final class Action: NSObject {
    let f: () -> Void
    init(_ f: @escaping () -> Void) { self.f = f }
    @objc func fire() { f() }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let info = Bundle.main.infoDictionary ?? [:]
    lazy var tandem = info["TandemScript"] as? String ?? "tandem"
    lazy var repo = info["RepoDir"] as? String ?? NSHomeDirectory()
    lazy var path = info["UserPATH"] as? String ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    lazy var mac = runProcess("/usr/sbin/scutil", ["--get", "ComputerName"], path: path).out
        .trimmingCharacters(in: .whitespacesAndNewlines)
    var status: NSStatusItem?
    var profiles: [Profile] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        s.button?.image = Self.statusIcon()
        s.button?.toolTip = "Claude Tandem"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        s.menu = menu
        status = s
    }

    // Rebuilt each time it opens, so it shows what is true now.
    func menuNeedsUpdate(_ menu: NSMenu) { build(menu) }

    func build(_ menu: NSMenu) {
        menu.removeAllItems()
        profiles = loadProfiles()
        header(menu, "Claude profiles on \(mac)")
        if profiles.isEmpty { header(menu, "Could not read profiles — try Run Doctor") }
        for p in profiles { menu.addItem(profileItem(p)) }
        menu.addItem(.separator())
        add(menu, "New Profile…") { [unowned self] in self.newProfile() }
        add(menu, "Sync Claude Code Sessions") { [unowned self] in self.terminal("\(q(self.tandem)) profile sync", title: "Sync sessions") }
        add(menu, "Run Doctor") { [unowned self] in self.terminal("\(q(self.tandem)) profile doctor", title: "Doctor") }
        menu.addItem(.separator())
        let login = add(menu, "Open at Login") { [unowned self] in self.toggleLogin() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(menu, "Quit Claude Tandem", key: "q") { NSApp.terminate(nil) }
    }

    // MARK: profiles

    func loadProfiles() -> [Profile] {
        let r = runProcess("/bin/bash", [tandem, "profile", "list", "--json"], path: path)
        guard r.code == 0, let data = r.out.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Profile].self, from: data)) ?? []
    }

    func side(_ p: Profile) -> String { p.isDefault ? mac : "\(mac)@\(p.id)" }

    func profileItem(_ p: Profile) -> NSMenuItem {
        let item = NSMenuItem()
        item.image = badgeImage(p, size: 24)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        let title = NSMutableAttributedString(string: p.name, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        let who = [p.email ?? "Claude Code not signed in", p.plan?.capitalized].compactMap { $0 }.joined(separator: " · ")
        title.append(NSAttributedString(string: "\n" + who, attributes: small))
        if p.stale {
            title.append(NSAttributedString(string: "  ·  Reopen to update",
                attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.systemOrange]))
        } else if p.open {
            title.append(NSAttributedString(string: "  ·  Open",
                attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.systemGreen]))
        }
        item.attributedTitle = title
        item.submenu = profileMenu(p)
        return item
    }

    func profileMenu(_ p: Profile) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        header(m, p.isDefault ? "\(side(p)) — Claude.app itself" : "\(side(p)) — id \(p.id)")
        add(m, p.open ? "Show Claude" : "Open Claude") { [unowned self] in self.openDesktop(p) }
        add(m, "Open Claude Code in Terminal") { [unowned self] in
            self.terminal("claude @\(p.id)", title: "Claude Code — \(p.name)", wait: false)
        }
        if p.stale {
            add(m, "Quit and Reopen (Claude was updated)") { [unowned self] in
                self.cli(["quit", p.id]) { self.cli(["desktop", p.id]) }
            }
        } else if p.open {
            add(m, "Quit Claude") { [unowned self] in self.cli(["quit", p.id]) }
        }
        m.addItem(.separator())
        add(m, "Hand Off a Project", nil).submenu = handoffMenu(from: p)
        add(m, "Receive a Project", nil).submenu = receiveMenu(as: p)
        m.addItem(.separator())
        add(m, "Rename…") { [unowned self] in self.rename(p) }
        add(m, "Change Badge…") { [unowned self] in self.changeBadge(p) }
        add(m, "Badge Colour", nil).submenu = colourMenu(p)
        return m
    }

    // MARK: handoffs

    func sharedRoot() -> String {
        let conf = NSHomeDirectory() + "/.config/claude-tandem/root"
        if let s = try? String(contentsOfFile: conf, encoding: .utf8),
           let line = s.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces), !line.isEmpty {
            return line.hasPrefix("~") ? NSHomeDirectory() + line.dropFirst() : line
        }
        return NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/Claude"
    }

    func dirs(_ path: String) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: path)) ?? []).filter { name in
            var isDir: ObjCBool = false
            return !name.hasPrefix(".") && fm.fileExists(atPath: path + "/" + name, isDirectory: &isDir) && isDir.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func sharedProjects() -> [String] { dirs(sharedRoot() + "/Projects") }

    /// Sides on other Macs, as named in ownership events ({ts}-{side}-{verb}.json) — the
    /// only place this Mac learns the other one's name.
    func otherSides() -> [String] {
        var found = Set<String>()
        let root = sharedRoot() + "/Projects"
        for proj in sharedProjects() {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: "\(root)/\(proj)/.handoff/events")) ?? []
            for f in files where f.hasSuffix(".json") {
                let stem = f.dropLast(5)
                guard let first = stem.firstIndex(of: "-"), let last = stem.lastIndex(of: "-"), first < last else { continue }
                let who = String(stem[stem.index(after: first)..<last])
                if who.split(separator: "@").first.map(String.init) != mac { found.insert(who) }
            }
        }
        return found.sorted()
    }

    func handoffMenu(from p: Profile) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let projects = sharedProjects()
        header(m, projects.isEmpty ? "No shared projects yet" : "Run /handoff in Cowork first — send needs its document")
        var targets: [(side: String, label: String)] = profiles.filter { $0.id != p.id }.map {
            (side($0), $0.isDefault ? "\(mac) — \($0.name)" : "\(side($0)) — \($0.name)")
        }
        targets += otherSides().map { ($0, "\($0) — other Mac") }
        for proj in projects {
            let sub = NSMenu()
            sub.autoenablesItems = false
            header(sub, targets.isEmpty ? "No other profile or Mac to send to" : "Send to")
            for t in targets {
                add(sub, t.label) { [unowned self] in
                    let who = p.isDefault ? "" : " --profile \(q(p.id))"
                    self.terminal("\(q(self.tandem))\(who) send \(q(proj)) --to \(q(t.side)) --wait",
                                  title: "Hand off \(proj) → \(t.side)")
                }
            }
            add(m, proj, nil).submenu = sub
        }
        return m
    }

    func receiveMenu(as p: Profile) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let projects = sharedProjects()
        header(m, projects.isEmpty ? "No shared projects yet" : "Receive as \(p.name)")
        for proj in projects {
            add(m, proj) { [unowned self] in
                var cmd = ""
                if p.open {
                    // receive adds a project to this profile's spaces.json, which a running
                    // Claude rewrites from memory — so it must be quit for a project new to it
                    cmd += "if read -q \(q("?Quit Claude (\(p.name)) first, so tandem can add the project if it is new here? [y/N] ")); "
                    cmd += "then echo; \(q(self.tandem)) profile quit \(q(p.id)); else echo; fi\n"
                }
                let who = p.isDefault ? "" : " --profile \(q(p.id))"
                cmd += "\(q(self.tandem))\(who) receive \(q(proj))"
                self.terminal(cmd, title: "Receive \(proj) as \(p.name)")
            }
        }
        return m
    }

    // MARK: actions

    func openDesktop(_ p: Profile) {
        if p.open, let pid = p.pid, let running = NSRunningApplication(processIdentifier: pid) {
            running.activate(options: [.activateAllWindows])
        } else {
            cli(["desktop", p.id])
        }
    }

    func rename(_ p: Profile) {
        guard let new = prompt("Rename “\(p.name)”",
            "The new name works everywhere: the launcher, claude @name, tandem --profile name. Its folders keep the id “\(p.id)”, so its logins and handoffs are untouched.",
            initial: p.name, ok: "Rename"), !new.isEmpty, new != p.name else { return }
        cli(["rename", p.id, new])
    }

    func changeBadge(_ p: Profile) {
        activate()
        let a = NSAlert()
        a.messageText = "Badge for “\(p.name)”"
        a.informativeText = "One or two letters in any script, or one emoji — or choose an image."
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Choose Image…")
        a.addButton(withTitle: "Use Initial")
        a.addButton(withTitle: "Cancel")
        let f = NSTextField(string: p.badgeImage == nil ? p.badge : "")
        f.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        a.accessoryView = f
        a.window.initialFirstResponder = f
        switch a.runModal() {
        case .alertFirstButtonReturn:
            let t = f.stringValue.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { cli(["app", p.id, "--badge", t]) }
        case .alertSecondButtonReturn:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.message = "Choose an image for \(p.name)’s badge"
            if panel.runModal() == .OK, let url = panel.url { cli(["app", p.id, "--badge-image", url.path]) }
        case .alertThirdButtonReturn:
            cli(["app", p.id, "--badge", "auto"])
        default: break
        }
    }

    func colourMenu(_ p: Profile) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        for (name, hex) in palette {
            let i = add(m, name) { [unowned self] in self.cli(["app", p.id, "--color", hex]) }
            i.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
                NSColor(hex: hex).setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); return true
            }
            if hex.caseInsensitiveCompare(p.color) == .orderedSame { i.state = .on }
        }
        return m
    }

    func newProfile() {
        guard let name = prompt("New profile",
            "A short name for the second account — letters, digits, - and _. You can rename it later.",
            initial: "", ok: "Create"), !name.isEmpty else { return }
        cli(["create", name]) {
            self.cli(["app", name]) {
                self.activate()
                let a = NSAlert()
                a.messageText = "“\(name)” is ready — now sign in"
                a.informativeText = "Sign in once in the desktop app and once in Claude Code. Use a private browser window when the sign-in page opens: otherwise claude.ai signs the new profile into the account it already has."
                a.addButton(withTitle: "Open Claude as \(name)")
                a.addButton(withTitle: "Open Claude Code")
                a.addButton(withTitle: "Later")
                switch a.runModal() {
                case .alertFirstButtonReturn: self.cli(["desktop", name])
                case .alertSecondButtonReturn: self.terminal("claude @\(name)", title: "Claude Code — \(name)", wait: false)
                default: break
                }
            }
        }
    }

    func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            alert("Couldn’t change Open at Login",
                  "\(error.localizedDescription)\n\nAdd it by hand: System Settings › General › Login Items › + and choose Claude Tandem in ~/Applications.")
        }
        if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: plumbing

    /// `tandem profile …`, off the main thread; an alert if it fails, `then` if it succeeds.
    func cli(_ args: [String], then: (() -> Void)? = nil) {
        let tandem = self.tandem, path = self.path
        DispatchQueue.global(qos: .userInitiated).async {
            let r = runProcess("/bin/bash", [tandem, "profile"] + args, path: path)
            DispatchQueue.main.async {
                if r.code == 0 { then?() } else {
                    self.alert("tandem profile \(args.first ?? "") didn’t work",
                               (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    /// A step whose output matters runs in Terminal, as a .command script in a login,
    /// interactive zsh — so the user's PATH and `claude @<profile>` are there.
    func terminal(_ command: String, title: String, wait: Bool = true) {
        var body = "#!/bin/zsh -il\ncd \(q(repo))\nprint -n \"\\e]0;\(title.replacingOccurrences(of: "\"", with: ""))\\a\"\n\(command)\n"
        if wait { body += "echo\nread -k1 '?Done — press any key to close. '\n" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-tandem-\(UUID().uuidString.prefix(8)).command")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch { alert("Couldn’t open Terminal", "\(error)"); return }
        _ = runProcess("/usr/bin/open", ["-a", "Terminal", url.path], path: path)
    }

    func activate() { NSApp.activate(ignoringOtherApps: true) }

    func prompt(_ title: String, _ message: String, initial: String, ok: String) -> String? {
        activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        let f = NSTextField(string: initial)
        f.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        a.accessoryView = f
        a.window.initialFirstResponder = f
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue.trimmingCharacters(in: .whitespaces) : nil
    }

    func alert(_ title: String, _ message: String) {
        activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    func header(_ m: NSMenu, _ text: String) {
        let i = NSMenuItem()
        i.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        i.isEnabled = false
        m.addItem(i)
    }

    @discardableResult
    func add(_ m: NSMenu, _ title: String, key: String = "", _ f: (() -> Void)?) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: key)
        if let f {
            let a = Action(f)
            i.target = a
            i.action = #selector(Action.fire)
            i.representedObject = a
        }
        m.addItem(i)
        return i
    }

    // MARK: drawing

    static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            for x in [1.5, 7.5] {
                let c = NSBezierPath(ovalIn: NSRect(x: x, y: 2.5, width: 11, height: 11))
                c.lineWidth = 1.6
                c.stroke()
            }
            return true
        }
        img.isTemplate = true   // follows the menu bar's light/dark appearance
        return img
    }

    func badgeImage(_ p: Profile, size: CGFloat) -> NSImage {
        let color = NSColor(hex: p.color)
        let pic = p.badgeImage.flatMap { NSImage(contentsOfFile: $0) }
        let badge = p.badge
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            circle.fill()
            if let pic {
                NSGraphicsContext.saveGraphicsState()
                circle.addClip()
                let s = min(pic.size.width, pic.size.height)
                pic.draw(in: r, from: NSRect(x: (pic.size.width - s) / 2, y: (pic.size.height - s) / 2, width: s, height: s),
                         operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                let emoji = badge.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
                let fs = size * (emoji ? 0.6 : (badge.count > 1 ? 0.4 : 0.52))
                var font = NSFont.systemFont(ofSize: fs, weight: .bold)
                if !emoji, let rounded = font.fontDescriptor.withDesign(.rounded) {
                    font = NSFont(descriptor: rounded, size: fs) ?? font
                }
                let s = NSAttributedString(string: badge, attributes: [.font: font, .foregroundColor: NSColor.white])
                let b = s.size()
                s.draw(at: NSPoint(x: r.midX - b.width / 2, y: r.midY - b.height / 2))
            }
            return true
        }
    }

    // MARK: self-check

    func dumpMenu(into dir: String) {
        let menu = NSMenu()
        build(menu)
        func walk(_ m: NSMenu, _ depth: Int) {
            for i in m.items {
                let t = i.isSeparatorItem ? "—" : (i.attributedTitle?.string ?? i.title).replacingOccurrences(of: "\n", with: " | ")
                print(String(repeating: "  ", count: depth) + t + (i.state == .on ? "  ✓" : ""))
                if let s = i.submenu { walk(s, depth + 1) }
            }
        }
        walk(menu, 0)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func save(_ img: NSImage, _ name: String) {
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: URL(fileURLWithPath: dir + "/" + name))
        }
        save(Self.statusIcon(), "status.png")
        for p in profiles { save(badgeImage(p, size: 96), "badge-\(p.id).png") }
    }
}

let app = NSApplication.shared
let delegate = App()
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--dump-menu") {
    delegate.dumpMenu(into: i + 1 < args.count ? args[i + 1] : NSTemporaryDirectory())
    exit(0)
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
