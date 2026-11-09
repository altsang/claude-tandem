// Claude Tandem — a menu-bar front end for bin/tandem (and its `tandem profile` half),
// with a window for the profiles and getting started (Window.swift).
//
// Every action is a call to `tandem`, so the CLI stays the single implementation and
// this file only draws the menu. The menu is for the profiles you have and what's waiting
// (the inbox); everything else — new profiles, settings, handoffs, the Macs — is in the
// window. Handoffs run inside the app with their steps shown (Handoffs.swift); only Claude
// Code opens in a terminal.
//
// Built by `tandem menubar`, which writes the script path and the user's PATH
// into Info.plist: an app started at login gets only /usr/bin:/bin.
//
// `ClaudeTandem --dump-menu <dir>` builds the menu without showing it, prints its
// tree and writes the icons it would draw into <dir>; the build checks itself with it.
// `ClaudeTandem --write-iconset <dir>` draws the app icon for the build to make an .icns.
import AppKit
import ServiceManagement
import SwiftUI

struct Profile: Decodable, Equatable, Identifiable {
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
    let dockIcon: Bool?
    let desktopAccount: String?
    let adoptable: Int?
    let launcher: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, plan, open, pid, stale, color, badge, adoptable, launcher
        case isDefault = "default", badgeImage = "badge_image", dockIcon = "dock_icon"
        case desktopAccount = "desktop_account"
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

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let info = Bundle.main.infoDictionary ?? [:]
    lazy var tandem = info["TandemScript"] as? String ?? "tandem"
    lazy var repo = info["RepoDir"] as? String ?? NSHomeDirectory()
    lazy var path = info["UserPATH"] as? String ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    // Read once, up front. A lazy var that runs a process can be re-entered — the window
    // redraws while scutil runs, reads `mac` again, and Swift traps (crash, 2026-11-01).
    let mac = runProcess("/usr/sbin/scutil", ["--get", "ComputerName"], path: "/usr/bin:/bin:/usr/sbin:/sbin").out
        .trimmingCharacters(in: .whitespacesAndNewlines)
    var status: NSStatusItem?
    var profiles: [Profile] = []
    var signInWatchers: [String: Timer] = [:]
    let store = Store()
    var window: NSWindow?
    var settingsWindow: NSWindow?
    let handoffsMenu = NSMenu(title: "Handoffs")

    func applicationDidFinishLaunching(_ n: Notification) {
        store.app = self
        let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        s.button?.image = Self.statusIcon()
        s.button?.toolTip = "Claude Tandem"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        s.menu = menu
        status = s
        NSApp.mainMenu = mainMenu()
        // the ledger runs whether or not the window is open: it is how handoffs get noticed
        store.notifier.store = store
        store.notifier.setup()
        store.startLedger()
        // Claude's updater relaunches a profile's Dock copy with no arguments, so it opens the
        // default account under that profile's badge (finding 29). Whenever a copy starts,
        // let `tandem profile repair` put it back; it does nothing when the copy is fine.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [unowned self] n in
            guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  a.bundleURL?.path.contains("/.config/claude-tandem/runtimes/") == true else { return }
            self.repairStrays()
        }
        repairStrays()
        // `--show <page>` (handoffs, macs, settings, setup, or a profile id) opens the window there.
        let argv = CommandLine.arguments
        if let i = argv.firstIndex(of: "--show"), i + 1 < argv.count {
            if argv[i + 1] == "settings" { showSettings() } else { showWindow(select: argv[i + 1]) }
            return
        }
        // First run, or only Claude.app itself so far: start with Get Started.
        let seen = UserDefaults.standard.bool(forKey: "welcomed")
        if !seen || loadProfiles().count < 2 {
            UserDefaults.standard.set(true, forKey: "welcomed")
            showWindow()
        }
    }

    // Opened again from Finder, Spotlight or the launcher: show the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return false
    }

    // MARK: the window

    /// While the window is open the app gets a Dock icon and ⌘-Tab, like any app;
    /// closing it goes back to living in the menu bar only.
    func showWindow(select: String? = nil, newProfile: Bool = false) {
        if window == nil {
            window = makeMainWindow(store: store)
            window?.delegate = self
        }
        if store.profiles.isEmpty { store.profiles = loadProfiles() }
        if let select { store.selection = select }
        // Get Started is the first page only until it's done; then the window opens on the
        // Inbox when something is waiting, else on Projects.
        else if store.selection == "setup" || store.selection == nil, store.setupLeft == 0 {
            store.selection = store.inbox.contains { $0.kind != .settling } ? "handoffs" : "projects"
        }
        NSApp.applicationIconImage = tandemAppIcon()
        NSApp.setActivationPolicy(.regular)
        store.windowOpen = true
        store.startPolling()
        store.refreshLedger()
        activate()
        window?.makeKeyAndOrderFront(nil)
        if newProfile { store.showNewProfile = true }
    }

    func windowWillClose(_ n: Notification) {
        guard let closing = n.object as? NSWindow else { return }
        closing.makeFirstResponder(nil)   // a field still being edited saves as the window closes
        if closing === window {
            store.stopPolling()
            store.windowOpen = false
        }
        // Back to living in the menu bar once neither window is left open.
        let others = [window, settingsWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// Settings, in a window of its own as on any Mac app: ⌘, from the app menu or the status
    /// menu. Three tabs in its toolbar, each one grouped form sized to what it holds.
    func showSettings(tab: Int? = nil) {
        if settingsWindow == nil {
            let tabs = SettingsTabs()
            func item(_ label: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
                let host = NSHostingController(rootView: view)
                host.sizingOptions = .preferredContentSize
                host.title = label   // the tab controller names the window after the selected tab
                let i = NSTabViewItem(viewController: host)
                i.label = label
                i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
                return i
            }
            tabs.tabStyle = .toolbar
            // General first, as in every Mac app's Settings; Maintenance, the occasional tools, last.
            tabs.addTabViewItem(item("General", "gearshape", GeneralSettings(store: store)))
            tabs.addTabViewItem(item("Handoffs", "arrow.left.arrow.right", HandoffsSettings(store: store)))
            tabs.addTabViewItem(item("Maintenance", "wrench.and.screwdriver", MaintenanceSettings(store: store)))
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable]
            w.toolbarStyle = .preference
            w.tabbingMode = .disallowed
            w.isReleasedWhenClosed = false
            w.delegate = self
            settingsWindow = w
            tabs.fit()
            w.center()
        }
        if let tab, let tabs = settingsWindow?.contentViewController as? SettingsTabs { tabs.selectedTabViewItemIndex = tab }
        NSApp.applicationIconImage = tandemAppIcon()
        NSApp.setActivationPolicy(.regular)
        activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// A new name for a profile, asked for in a small sheet-like alert (the sidebar's Rename…).
    func renameProfile(_ p: Profile) {
        guard let n = prompt("Rename \(p.name)", "Letters, digits, - and _. Its folders keep the id “\(p.id)”, so sign-ins and handoffs are untouched.",
                             initial: p.name, ok: "Rename"), n != p.name else { return }
        guard validName(n) || (p.isDefault && n == "default"),
              !store.profiles.contains(where: { $0.id != p.id && ($0.name == n || $0.id == n) }) else {
            alert("Can’t use “\(n)”", "Use letters, digits, - and _, and a name no other profile has."); return
        }
        cli(["rename", p.id, n])
    }

    // MARK: the main menu — shown while a window is open

    func mainMenu() -> NSMenu {
        let bar = NSMenu()
        func top(_ title: String, _ m: NSMenu) { let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.submenu = m; bar.addItem(i) }
        func std(_ m: NSMenu, _ title: String, _ sel: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.keyEquivalentModifierMask = mods; m.addItem(i)
        }
        func go(_ m: NSMenu, _ title: String, _ key: String, _ page: String) {
            add(m, title, key: key) { [unowned self] in self.showWindow(select: page) }
        }

        let appMenu = NSMenu(title: "Claude Tandem")
        std(appMenu, "About Claude Tandem", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "")
        appMenu.addItem(.separator())
        add(appMenu, "Settings…", key: ",") { [unowned self] in self.showSettings() }
        appMenu.addItem(.separator())
        std(appMenu, "Hide Claude Tandem", #selector(NSApplication.hide(_:)), "h")
        std(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        std(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)), "")
        appMenu.addItem(.separator())
        std(appMenu, "Quit Claude Tandem", #selector(NSApplication.terminate(_:)), "q")
        top("Claude Tandem", appMenu)

        let file = NSMenu(title: "File")
        add(file, "New Profile…", key: "n") { [unowned self] in self.showWindow(newProfile: true) }
        file.addItem(.separator())
        std(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        top("File", file)

        let edit = NSMenu(title: "Edit")
        std(edit, "Undo", Selector(("undo:")), "z")
        std(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        std(edit, "Cut", #selector(NSText.cut(_:)), "x")
        std(edit, "Copy", #selector(NSText.copy(_:)), "c")
        std(edit, "Paste", #selector(NSText.paste(_:)), "v")
        std(edit, "Delete", #selector(NSText.delete(_:)), "")
        std(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        top("Edit", edit)

        let view = NSMenu(title: "View")
        std(view, "Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control])
        view.addItem(.separator())
        go(view, "Get Started", "1", "setup")
        go(view, "Inbox", "2", "handoffs")
        go(view, "Projects", "3", "projects")
        go(view, "Macs", "4", "macs")
        view.addItem(.separator())
        std(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        top("View", view)

        handoffsMenu.delegate = self
        handoffsMenu.autoenablesItems = false
        top("Handoffs", handoffsMenu)

        let win = NSMenu(title: "Window")
        std(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        std(win, "Zoom", #selector(NSWindow.performZoom(_:)), "")
        win.addItem(.separator())
        std(win, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "")
        top("Window", win)
        NSApp.windowsMenu = win

        let help = NSMenu(title: "Help")
        let site = "https://github.com/altsang/claude-tandem/blob/main/"
        for (t, path) in [("Claude Tandem Help", "README.md"), ("Handoffs Guide", "docs/handoffs.md"), ("Troubleshooting", "docs/troubleshooting.md")] {
            add(help, t) { NSWorkspace.shared.open(URL(string: site + path)!) }
        }
        help.addItem(.separator())
        go(help, "Get Started Checklist", "", "setup")
        top("Help", help)
        NSApp.helpMenu = help
        return bar
    }

    /// The Handoffs menu, rebuilt as it opens: Check Now, then what can be done right now.
    func buildHandoffsMenu(_ m: NSMenu) {
        m.removeAllItems()
        add(m, "Check Now", key: "r") { [unowned self] in self.store.refreshLedger() }
        m.addItem(.separator())
        let all = store.ledger?.projects ?? []
        let held = all.filter { store.isMine($0.holder) && $0.state == "held" }
        let arriving = all.filter { store.isMine($0.holder) && $0.state == "sent" }
        if held.isEmpty {
            add(m, "Hand Off Project…", key: "H", nil).isEnabled = false
        }
        for (n, x) in held.enumerated() {
            let i = add(m, "Hand Off \(x.name)…", key: n == 0 ? "H" : "") { [unowned self] in
                self.showWindow(select: "handoffs")
                self.store.draft(x.name, from: x.holder ?? "")
            }
            if held.count > 1 { i.title += " — \(store.label(x.holder ?? ""))" }
        }
        for x in arriving {
            add(m, "Receive \(x.name) as \(store.label(x.holder ?? ""))") { [unowned self] in
                self.store.startReceive(x.name, as: x.holder ?? "")
                self.showWindow(select: "handoffs")
            }
        }
        let others = all.filter { !store.isMine($0.holder) && $0.holder != nil }
        let ask = add(m, "Ask for a Project", nil)
        if others.isEmpty || store.profiles.isEmpty { ask.isEnabled = false } else {
            let sub = NSMenu(); sub.autoenablesItems = false
            for x in others {
                if store.profiles.count == 1, let pr = store.profiles.first {
                    add(sub, x.name) { [unowned self] in self.store.ask(x.name, as: self.side(pr)) }
                } else {
                    let pm = NSMenu(); pm.autoenablesItems = false
                    for pr in store.profiles { add(pm, "As \(pr.name)") { [unowned self] in self.store.ask(x.name, as: self.side(pr)) } }
                    add(sub, x.name, nil).submenu = pm
                }
            }
            ask.submenu = sub
        }
    }

    // Rebuilt each time it opens, so it shows what is true now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === handoffsMenu { buildHandoffsMenu(menu) } else { build(menu) }
    }

    func build(_ menu: NSMenu) {
        menu.removeAllItems()
        profiles = loadProfiles()
        store.refreshLedger()
        // the inbox first: what's waiting needs one click
        let inbox = store.inbox
        if !inbox.isEmpty {
            header(menu, "Waiting for you")
            for item in inbox { inboxItem(menu, item) }
            menu.addItem(.separator())
        }
        header(menu, "Claude profiles on \(mac)")
        if profiles.isEmpty { header(menu, "Could not read profiles — run Settings… › Maintenance › Run Doctor") }
        for p in profiles { menu.addItem(profileItem(p)) }
        menu.addItem(.separator())
        add(menu, "Open Claude Tandem…") { [unowned self] in self.showWindow() }
        add(menu, "Settings…", key: ",") { [unowned self] in self.showSettings() }
        menu.addItem(.separator())
        add(menu, "Quit Claude Tandem", key: "q") { NSApp.terminate(nil) }
    }

    func inboxItem(_ menu: NSMenu, _ item: InboxItem) {
        let p = item.project.name
        let who = profiles.first { side($0) == item.side }?.name ?? item.side
        switch item.kind {
        case .arrival:
            add(menu, "↓ Receive \(p) as \(who) — from \(store.label(item.other ?? "?"))") { [unowned self] in
                self.store.startReceive(p, as: item.side)
                self.showWindow(select: "handoffs")
            }
        case .brief:
            add(menu, "↑ Send \(p)… — brief ready") { [unowned self] in
                self.showWindow(select: "handoffs")
                self.store.draft(p, from: item.side)
            }
        case .request:
            add(menu, "? \(self.store.label(item.other ?? "?")) asks for \(p)…") { [unowned self] in
                self.showWindow(select: "handoffs")
                self.store.draft(p, from: item.side, to: item.other)
            }
        case .delivered:
            break
        case .settling:
            let open = profiles.first { side($0) == item.side }?.open ?? false
            add(menu, open ? "⏸ \(p): quit \(who)’s Claude to finish" : "⏸ Finish setting up \(p)") { [unowned self] in
                if open { self.store.quitAndFinish(p, as: item.side) } else { self.store.startSettle(p, as: item.side) }
            }
        }
    }

    /// The menu-bar icon carries a dot while something is waiting.
    func updateStatusIcon() {
        let n = store.inbox.filter { $0.kind != .settling }.count
        status?.button?.image = n > 0 ? Self.statusIconDot() : Self.statusIcon()
        status?.button?.toolTip = n > 0 ? "Claude Tandem — \(n) waiting" : "Claude Tandem"
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
        if let n = p.adoptable, n > 0 {
            title.append(NSAttributedString(string: "  ·  \(n) earlier session\(n == 1 ? "" : "s") to bring in",
                attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.systemBlue]))
        }
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
        add(m, "Open Claude Code in Terminal") { [unowned self] in self.openCode(p.id, name: p.name) }
        if p.stale {
            add(m, "Quit and Reopen (Claude was updated)") { [unowned self] in
                self.cli(["quit", p.id]) { self.cli(["desktop", p.id]) }
            }
        } else if p.open {
            add(m, "Quit Claude") { [unowned self] in self.cli(["quit", p.id]) }
        }
        let me = side(p)
        let all = store.ledger?.projects ?? []
        let held = all.filter { $0.holder == me && $0.state == "held" }
        let coming = all.filter { $0.holder == me && $0.state == "sent" }
        if !held.isEmpty || !coming.isEmpty { m.addItem(.separator()) }
        for x in coming {
            add(m, "Receive \(x.name) — from \(store.label(x.last?.machine ?? ""))") { [unowned self] in
                self.store.startReceive(x.name, as: me)
                self.showWindow(select: "handoffs")
            }
        }
        if !held.isEmpty {
            let sub = NSMenu()
            sub.autoenablesItems = false
            header(sub, "Projects \(p.name) holds")
            for x in held {
                add(sub, x.name + (x.intents.isEmpty ? "…" : " — brief ready…")) { [unowned self] in
                    self.showWindow(select: "handoffs")
                    self.store.draft(x.name, from: me)
                }
            }
            add(m, "Hand Off", nil).submenu = sub
        }
        m.addItem(.separator())
        if let n = p.adoptable, n > 0 {
            add(m, "Bring In Earlier Sessions (\(n))…") { [unowned self] in self.adoptWizard(p.id) }
        }
        add(m, "Show in Claude Tandem…") { [unowned self] in self.showWindow(select: p.id) }
        return m
    }

    // MARK: actions

    /// Brings a profile's Claude forward with a window — reopening it the way a Dock click
    /// does, since Claude keeps running after its last window closes, and activating alone
    /// shows nothing. A profile's own badged copy has a path of its own, so `open` on it
    /// reaches that profile; one running from /Applications/Claude.app shares the default's
    /// path, so it goes through `tandem profile desktop`, which hands Claude its data folder
    /// and lets the running copy take it.
    func openDesktop(_ p: Profile) {
        guard p.open, let pid = p.pid, let running = NSRunningApplication(processIdentifier: pid),
              let url = running.bundleURL else { cli(["desktop", p.id]); return }
        let shared = url.standardizedFileURL.path == "/Applications/Claude.app"
        if p.isDefault || !shared {
            let path = self.path
            DispatchQueue.global(qos: .userInitiated).async {
                _ = runProcess("/usr/bin/open", ["-a", url.path], path: path)
                DispatchQueue.main.async { running.activate(options: [.activateAllWindows]) }
            }
        } else {
            cli(["desktop", p.id])
        }
    }

    /// Claude Code as the profile, in Terminal. Through tandem rather than `claude @p`,
    /// which needs a shell hook a Homebrew install doesn't have.
    func openCode(_ id: String, name: String) {
        terminal("\(q(tandem)) profile code \(q(id))", title: "Claude Code — \(name)", wait: false)
    }

    /// The /handoff skill's SKILL.md, selected in Finder.
    func showSkill() {
        let r = runProcess("/bin/bash", [tandem, "skill", "--print"], path: path)
        let f = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.code == 0, !f.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) }
        else { alert("Couldn’t find the /handoff skill", (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines)) }
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

    // MARK: adopt — the setup wizard's last step

    /// A new profile's account is only known once its desktop app is signed in, so after
    /// New Profile → Open Claude, look every few seconds (for up to 20 minutes) for the
    /// sign-in to land, then offer what that account left in the regular Claude.
    func watchForSignIn(_ id: String) {
        signInWatchers[id]?.invalidate()
        let started = Date()
        signInWatchers[id] = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [unowned self] t in
            if Date().timeIntervalSince(started) > 1200 { t.invalidate(); self.signInWatchers[id] = nil; return }
            guard let p = self.loadProfiles().first(where: { $0.id == id }), p.desktopAccount != nil else { return }
            t.invalidate(); self.signInWatchers[id] = nil
            if (p.adoptable ?? 0) > 0 { self.adoptWizard(id) }
        }
    }

    func adoptWizard(_ id: String) {
        let r = runProcess("/bin/bash", [tandem, "profile", "adopt", id, "--dry-run", "--json"], path: path)
        guard let data = r.out.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = j["sessions"] as? [[String: Any]], !sessions.isEmpty,
              let p = loadProfiles().first(where: { $0.id == id }) else { return }
        let titles = sessions.prefix(6).map { "  ·  " + (($0["title"] as? String) ?? "untitled") }
        let more = sessions.count > 6 ? "\n  ·  …and \(sessions.count - 6) more" : ""
        let cowork = (j["cowork_projects"] as? Int ?? 0) + (j["cowork_sessions"] as? Int ?? 0)
        activate()
        let a = NSAlert()
        a.messageText = "Bring \(p.name)’s earlier work in?"
        a.informativeText = "\(p.name) is signed in\(p.email.map { " as " + $0 } ?? ""). Before it had its own profile, this account was used in your regular Claude app, which still has \(sessions.count) Claude Code session\(sessions.count == 1 ? "" : "s") from it:\n\n"
            + titles.joined(separator: "\n") + more
            + "\n\nThey’ll be copied — your regular Claude keeps its own. "
            + (p.open ? "\(p.name) will close for a moment and reopen." : "")
            + (cowork > 0 ? "\n\nIt also left Claude projects or sessions there; those aren’t moved yet." : "")
        a.addButton(withTitle: "Copy Them")
        a.addButton(withTitle: "Not Now")
        a.addButton(withTitle: "Never for This Profile")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            cli(["adopt", id, "--restart"]) {
                self.alert("Done", "\(sessions.count) session\(sessions.count == 1 ? " is" : "s are") now in \(p.name)’s Code tab.")
            }
        case .alertThirdButtonReturn:
            cli(["adopt", id, "--never"])
        default: break
        }
    }

    // MARK: plumbing

    /// `tandem profile …`, off the main thread; an alert (and `onFail`) if it fails, `then`
    /// if it succeeds. Either way the window re-reads the profiles.
    func cli(_ args: [String], then: (() -> Void)? = nil) { cli(args, onFail: nil, then: then) }

    func cli(_ args: [String], onFail: (() -> Void)?, then: (() -> Void)?) {
        let tandem = self.tandem, path = self.path
        DispatchQueue.global(qos: .userInitiated).async {
            let r = runProcess("/bin/bash", [tandem, "profile"] + args, path: path)
            DispatchQueue.main.async {
                if r.code == 0 { then?() } else {
                    onFail?()
                    self.alert("tandem profile \(args.first ?? "") didn’t work",
                               (r.err + r.out).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                self.store.refresh()
            }
        }
    }

    /// Runs `tandem profile repair` and says what it did: nothing to say when every
    /// Dock copy is running as its own profile.
    func repairStrays() {
        let tandem = self.tandem, path = self.path
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            let r = runProcess("/bin/bash", [tandem, "profile", "repair"], path: path)
            guard r.out.contains("updater reopened") else { return }
            let names = r.out.components(separatedBy: "\n").compactMap { line -> String? in
                guard line.contains("updater reopened"), let a = line.range(of: "for '"),
                      let b = line.range(of: "'", range: a.upperBound..<line.endIndex) else { return nil }
                return String(line[a.upperBound..<b.lowerBound])
            }
            let who = names.isEmpty ? "A profile" : names.joined(separator: ", ")
            DispatchQueue.main.async {
                let fixed = r.code == 0
                self.store.notifier.post(id: "repair:\(Date().timeIntervalSince1970)",
                    title: fixed ? "\(who) reopened on its own account" : "\(who) is showing your default account",
                    body: fixed ? "Claude’s updater had restarted it on your default account. Claude Tandem quit it and opened it again as \(who)."
                                : "Claude’s updater restarted it on your default account, and it didn’t quit. Quit it, then open it from its Claude (\(who)) launcher.",
                    category: "INFO", info: [:])
                self.store.refresh()
            }
        }
    }

    /// The terminal steps open in: the choice in Settings, else Ghostty if it's installed,
    /// else Terminal.
    var terminalApp: String {
        if let t = UserDefaults.standard.string(forKey: "terminal"), t != "Ghostty" || ghosttyInstalled { return t }
        return ghosttyInstalled ? "Ghostty" : "Terminal"
    }
    var ghosttyInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil }

    /// A step whose output matters runs in a terminal, as a .command script in a login,
    /// interactive zsh — so the user's PATH and `claude @<profile>` are there.
    func terminal(_ command: String, title: String, wait: Bool = true) {
        var body = "#!/bin/zsh -il\ncd \(q(repo))\nprint -n \"\\e]0;\(title.replacingOccurrences(of: "\"", with: ""))\\a\"\n\(command)\n"
        if wait { body += "echo\nread -k1 '?Done — press any key to close. '\n" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-tandem-\(UUID().uuidString.prefix(8)).command")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch { alert("Couldn’t open a terminal", "\(error)"); return }
        if terminalApp == "Ghostty", openInGhostty(url.path) { return }
        _ = runProcess("/usr/bin/open", ["-a", "Terminal", url.path], path: path)
    }

    /// A new window in the Ghostty that's already running, through its AppleScript — not
    /// `open -na Ghostty`, which starts a second Ghostty that restores all your saved windows.
    /// macOS asks once whether Claude Tandem may control Ghostty; if not, Terminal it is.
    func openInGhostty(_ script: String) -> Bool {
        let esc = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "tell application id \"com.mitchellh.ghostty\"\nactivate\nnew window with configuration {command:\"\(esc)\"}\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        guard let err else { return true }
        let n = err[NSAppleScript.errorNumber] as? Int ?? 0
        alert("Opened in Terminal instead of Ghostty",
              n == -1743 ? "Claude Tandem isn’t allowed to control Ghostty. Allow it in System Settings › Privacy & Security › Automation › Claude Tandem."
                         : "Ghostty didn’t open a window: \(err[NSAppleScript.errorMessage] as? String ?? "error \(n)").")
        return false
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

    // The logo in miniature (assets/gen-logo.py): two Clawds on a tandem, one block per character.
    // Blocks are taller than wide, like Clawd's terminal characters.
    static let iconSprite = [
        ".#######...#######...",
        ".#.###.#...#.###.#...",
        "#########.##########.",
        ".#######...#######.#.",
        "..#.#.#.....#.#.#..#.",
        "..#################..",
        "..#...............#..",
        ".###.............###.",
        "#...#...........#...#",
        ".###.............###.",
    ]

    static func statusIcon() -> NSImage {
        let bw: CGFloat = 1, bh: CGFloat = 1.5
        let size = NSSize(width: CGFloat(iconSprite[0].count) * bw, height: CGFloat(iconSprite.count) * bh)
        let img = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (j, row) in iconSprite.enumerated() {
                for (i, ch) in row.enumerated() where ch == "#" {
                    NSRect(x: CGFloat(i) * bw, y: CGFloat(j) * bh, width: bw, height: bh).fill()
                }
            }
            return true
        }
        img.isTemplate = true   // follows the menu bar's light/dark appearance
        return img
    }

    /// The icon with a dot in its top-right corner: something is waiting. Not a template, so
    /// the dot keeps its colour; the bike follows the menu bar's appearance by hand.
    static func statusIconDot() -> NSImage {
        let base = statusIcon()
        let size = NSSize(width: base.size.width + 4, height: base.size.height)
        let img = NSImage(size: size, flipped: false) { r in
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let tinted = NSImage(size: base.size, flipped: false) { rr in
                base.draw(in: rr)
                (dark ? NSColor.white : NSColor.black).set()
                rr.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(origin: .zero, size: base.size))
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: r.maxX - 6, y: r.maxY - 6, width: 6, height: 6)).fill()
            return true
        }
        img.isTemplate = false
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
        // what the menu would show with the ledger read: synchronously, since nothing runs here
        store.app = self
        store.profiles = loadProfiles()
        let r = runProcess("/bin/bash", [tandem, "where", "--json"], path: path)
        store.ledger = try? JSONDecoder().decode(Ledger.self, from: Data(r.out.utf8))
        if store.ledger == nil { print("(could not read the ledger: \(r.err.prefix(200)))") }
        store.ledgerLoading = true   // build() must not start an async read
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

/// Settings' tabs. Each tab is sized to its form; switching tabs resizes the window to it,
/// keeping its top edge where it was, as System Settings-era preference windows do.
final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        fit()
    }
    func fit() {
        guard let w = view.window, let v = tabViewItems[selectedTabViewItemIndex].viewController?.view else { return }
        let size = v.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let frame = w.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var f = w.frame
        f.origin.y += f.height - frame.height
        f.size = frame.size
        w.setFrame(f, display: true, animate: w.isVisible)
    }
}

let app = NSApplication.shared
let delegate = App()
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--write-iconset"), i + 1 < args.count {
    exit(writeIconset(to: args[i + 1]) ? 0 : 1)
}
if let i = args.firstIndex(of: "--dump-menu") {
    delegate.dumpMenu(into: i + 1 < args.count ? args[i + 1] : NSTemporaryDirectory())
    exit(0)
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
