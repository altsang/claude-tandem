// Claude Tandem's window: the profiles, a Get Started checklist, and a New Profile sheet.
//
// Like the menu, it holds no logic of its own: every change is a `tandem profile …` call
// made through App.cli, and what it shows comes from `tandem profile list --json`,
// re-read every few seconds while the window is open.
import AppKit
import ServiceManagement
import SwiftUI

// MARK: state

/// `@State` without the macro. In the macOS 27 SDK `@State` is a SwiftUI macro whose plugin
/// (libSwiftUIMacros) ships with Xcode only — the Command Line Tools that build this app don't
/// have it, so `@State` fails there ("plugin for module 'SwiftUIMacros' not found"; Ji-su,
/// 2026-11-02). Holding a SwiftUI.State as a plain stored property is what the macro expands
/// to; SwiftUI finds it inside this DynamicProperty and keeps it across updates the same way.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let state: SwiftUI.State<Value>
    init(wrappedValue: Value) { state = SwiftUI.State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}


final class Store: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selection: String? = "setup"
    @Published var showNewProfile = false
    @Published var loaded = false
    weak var app: App?
    private var timer: Timer?
    private var loading = false

    // the ledger and its jobs: Handoffs.swift
    @Published var ledger: Ledger?
    @Published var jobs: [Job] = []
    @Published var sendDraft: SendDraft?
    @Published var logJob: Job?
    @Published var settingsLogJob: Job?   // maintenance output, shown over the Settings window
    @Published var ledgerAt: Date?        // when the ledger was last read
    @Published var config: [String: String] = [:]   // `tandem config`, shared with the CLI and tandem watch
    var ledgerLoading = false
    var ledgerTimer: Timer?
    var ledgerTicks = 0
    var windowOpen = false
    let notifier = Notifier()

    func refresh() {
        guard !loading, let app else { return }
        loading = true
        let tandem = app.tandem, path = app.path
        DispatchQueue.global(qos: .userInitiated).async {
            let r = runProcess("/bin/bash", [tandem, "profile", "list", "--json"], path: path)
            let ps = r.code == 0 ? (try? JSONDecoder().decode([Profile].self, from: Data(r.out.utf8))) : nil
            DispatchQueue.main.async {
                if let ps, ps != self.profiles { self.profiles = ps }
                self.loaded = true
                self.loading = false
            }
        }
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    /// The profile the Get Started steps are about: the first one that isn't Claude.app itself.
    var second: Profile? { profiles.first { !$0.isDefault } }

    /// Get Started's steps, done or not, in its order. The page and the sidebar's count both
    /// read this, so they can't disagree.
    var setupSteps: [Bool] {
        let p = second
        return [FileManager.default.fileExists(atPath: "/Applications/Claude.app"),
                p != nil, p?.desktopAccount != nil, p?.email != nil,
                p?.launcher.map(dockPinned) ?? false,
                UserDefaults.standard.bool(forKey: "skillAdded"),
                SMAppService.mainApp.status == .enabled]
    }
    var setupLeft: Int { setupSteps.filter { !$0 }.count }
}

/// Whether the Dock keeps this app pinned. Read from the Dock's own preferences.
func dockPinned(_ path: String) -> Bool {
    CFPreferencesAppSynchronize("com.apple.dock" as CFString)
    guard let apps = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]]
    else { return false }
    let want = URL(fileURLWithPath: path).standardizedFileURL.path
    return apps.contains { tile in
        guard let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
              let s = file["_CFURLString"] as? String, let url = URL(string: s) else { return false }
        return url.standardizedFileURL.path == want
    }
}

// MARK: the window

func makeMainWindow(store: Store) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                     styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                     backing: .buffered, defer: false)
    w.title = "Claude Tandem"
    w.isReleasedWhenClosed = false
    w.tabbingMode = .disallowed   // one window: no tab bar items in View or Window
    w.contentMinSize = NSSize(width: 720, height: 480)
    w.contentView = NSHostingView(rootView: MainView(store: store))
    w.center()
    w.setFrameAutosaveName("ClaudeTandemMain")
    return w
}

struct MainView: View {
    @ObservedObject var store: Store
    @ViewState private var hoverProfiles = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section {
                    // Get Started only while something is left to do; Help › Get Started Checklist
                    // still opens it afterwards.
                    if store.setupLeft > 0 || store.selection == "setup" {
                        Label("Get Started", systemImage: "checklist")
                            .badge(store.setupLeft)
                            .tag("setup")
                    }
                    // the tag goes last: a modifier after it wraps the row, and List then can't select it
                    // the Inbox keeps the "handoffs" tag: notifications and menus open it by that name
                    Label("Inbox", systemImage: "tray")
                        .badge(store.inbox.filter { $0.kind != .settling }.count)
                        .tag("handoffs")
                    Label("Projects", systemImage: "square.grid.3x3").tag("projects")
                    Label("Macs", systemImage: "laptopcomputer.and.iphone").tag("macs")
                }
                Section {
                    ForEach(store.profiles) { p in
                        ProfileRow(store: store, p: p)
                            .contextMenu { ProfileMenu(store: store, p: p) }
                            .tag(p.id)
                    }
                } header: {
                    HStack {
                        Text("Profiles")
                        Spacer()
                        // New Profile lives in File › New Profile… ⌘N; this is the shortcut to it
                        // where the profiles are, shown on hover like Finder's sidebar controls.
                        Button { store.showNewProfile = true } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                            .help("New Profile… (⌘N)")
                            .accessibilityLabel("New Profile")
                            .opacity(hoverProfiles ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hoverProfiles = $0 }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if store.selection == "setup" || store.selection == nil {
                GetStartedView(store: store)
                    .navigationTitle("Get Started")
                    .navigationSubtitle(store.setupLeft == 0 ? "All set" : "\(store.setupLeft) step\(store.setupLeft == 1 ? "" : "s") left")
            } else if store.selection == "handoffs" {
                HandoffsView(store: store).navigationTitle("Inbox")
            } else if store.selection == "projects" {
                ProjectsView(store: store).navigationTitle("Projects")
            } else if store.selection == "macs" {
                MacsView(store: store).navigationTitle("Macs")
            } else if let p = store.profiles.first(where: { $0.id == store.selection }) {
                ProfileDetail(store: store, p: p).id(p.id)   // fresh fields per profile
                    .navigationTitle(p.name)
                    .navigationSubtitle(profileLine(p, email: true))
            } else if store.loaded {
                Text("That profile is gone.").foregroundStyle(.secondary).navigationTitle("Profiles")
            } else {
                ProgressView()
            }
        }
        .sheet(isPresented: $store.showNewProfile) { NewProfileSheet(store: store) }
        .sheet(item: $store.logJob) { job in LogSheet(job: job) }
        .sheet(item: $store.sendDraft) { d in SendSheet(store: store, draft: d) }
    }
}

/// A profile's actions, for its right-click menu in the sidebar — the same ones as its
/// submenu in the menu bar.
struct ProfileMenu: View {
    @ObservedObject var store: Store
    let p: Profile
    var body: some View {
        let app = store.app, side = app?.side(p) ?? p.id
        let all = store.ledger?.projects ?? []
        let held = all.filter { $0.holder == side && $0.state == "held" }
        let coming = all.filter { $0.holder == side && $0.state == "sent" }
        Button(p.open ? "Show Claude" : "Open Claude") { app?.openDesktop(p) }
        Button("Open Claude Code") { app?.openCode(p.id, name: p.name) }
        if p.stale {
            Button("Quit and Reopen") { app?.cli(["quit", p.id]) { app?.cli(["desktop", p.id]) } }
        } else if p.open {
            Button("Quit Claude") { app?.cli(["quit", p.id]) }
        }
        if !held.isEmpty || !coming.isEmpty { Divider() }
        ForEach(coming) { x in
            Button("Receive \(x.name)") { store.selection = "handoffs"; store.startReceive(x.name, as: side) }
        }
        if !held.isEmpty {
            Menu("Hand Off") {
                ForEach(held) { x in Button(x.name + "…") { store.selection = "handoffs"; store.draft(x.name, from: side) } }
            }
        }
        Divider()
        Button("Rename…") { app?.renameProfile(p) }
    }
}

struct Badge: View {
    let store: Store
    let p: Profile
    let size: CGFloat
    var body: some View {
        if let img = store.app?.badgeImage(p, size: size) {
            Image(nsImage: img).frame(width: size, height: size)
        }
    }
}

struct ProfileRow: View {
    let store: Store
    let p: Profile
    var body: some View {
        HStack(spacing: 10) {
            Badge(store: store, p: p, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).fontWeight(.semibold)
                Text(profileLine(p, email: false)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if p.stale {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
            } else if p.open {
                Circle().fill(.green).frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
        .help(p.email ?? "Claude Code not signed in")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.name), \(profileLine(p, email: false))")
    }
}

/// "you@x.com · Max · Claude open": a profile's account and whether its Claude runs, in words.
func profileLine(_ p: Profile, email: Bool) -> String {
    let state = p.stale ? "Reopen to update" : (p.open ? "Claude open" : "Claude closed")
    return [email ? (p.email ?? "Claude Code not signed in") : nil, p.plan?.capitalized, state]
        .compactMap { $0 }.joined(separator: " · ")
}

func who(_ p: Profile) -> String {
    [p.email ?? "Claude Code not signed in", p.plan?.capitalized].compactMap { $0 }.joined(separator: " · ")
}

// MARK: a profile

struct ProfileDetail: View {
    @ObservedObject var store: Store
    let p: Profile

    var app: App? { store.app }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Projects") { ProfileProjects(store: store, p: p).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                GroupBox("Accounts") { accounts.frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                if let n = p.adoptable, n > 0 {
                    GroupBox("Earlier sessions") {
                        HStack {
                            Text("Before it had its own profile, this account was used in your regular Claude. \(n) Claude Code session\(n == 1 ? " is" : "s are") still there.")
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Bring Them In…") { app?.adoptWizard(p.id) }
                        }.padding(6)
                    }
                }
                GroupBox("Name") { nameBox.frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                GroupBox("Badge") { badgeBox.frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                if !p.isDefault {
                    GroupBox("Dock") { dockBox.frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        // A click on empty space ends editing, which saves the field, as in any Mac window.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) })
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(p.open ? "Show Claude" : "Open Claude") { app?.openDesktop(p) }
                    .help(p.open ? "Bring \(p.name)’s Claude forward" : "Open Claude as \(p.name)")
                Button { app?.openCode(p.id, name: p.name) } label: { Label("Open Claude Code", systemImage: "terminal") }
                    .help("Open Claude Code as \(p.name)")
                if p.stale {
                    Button { app?.cli(["quit", p.id]) { self.app?.cli(["desktop", p.id]) } } label: {
                        Label("Quit and Reopen", systemImage: "arrow.clockwise")
                    }.help("Claude was updated: quit and reopen \(p.name) to run the new version")
                } else {
                    Button { app?.cli(["quit", p.id]) } label: { Label("Quit Claude", systemImage: "power") }
                        .help("Quit \(p.name)’s Claude").disabled(!p.open)
                }
            }
        }
    }

    /// A new name, saved when editing ends. Unchanged: nothing. Not allowed: beep, and the
    /// field goes back to the current name.
    func saveName(_ raw: String) -> Bool {
        let n = raw.trimmingCharacters(in: .whitespaces)
        if n == p.name { return true }
        guard validName(n) || (p.isDefault && n == "default"),
              !store.profiles.contains(where: { $0.id != p.id && ($0.name == n || $0.id == n) }) else {
            NSSound.beep(); return false
        }
        app?.cli(["rename", p.id, n])
        return true
    }

    /// Letters or an emoji, saved when editing ends; empty goes back to the initial (and drops an image).
    func saveBadge(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            app?.cli(["app", p.id, "--badge", "auto"])
        } else if t != p.badge || p.badgeImage != nil {
            app?.cli(["app", p.id, "--badge", t])
        }
        return true
    }

    var accounts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Profile").foregroundStyle(.secondary)
                Text(p.isDefault ? "Claude.app itself — the account you had before Tandem"
                                 : "id “\(p.id)” · handoff side \(app?.side(p) ?? p.id)")
            }
            GridRow {
                Text("Claude").foregroundStyle(.secondary)
                if let a = p.desktopAccount {
                    Text("Signed in · account \(a)")
                } else {
                    Text("Not signed in yet. Open Claude and sign in — use a private browser window when the sign-in page opens, or claude.ai signs it into the account it already has.")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            GridRow {
                Text("Claude Code").foregroundStyle(.secondary)
                if p.email != nil {
                    Text(who(p))
                } else {
                    Text("Not signed in yet. Open Claude Code and sign in once.")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    var nameBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            CommitField(value: p.name, placeholder: "Name", commit: saveName).frame(maxWidth: 240)
            Text(p.isDefault
                 ? "Shown here and in the menu bar, and works with tandem --profile. It stays Claude.app itself, and “default” keeps working too."
                 : "Works everywhere the id “\(p.id)” does — tandem --profile, the menu bar. The folders keep the id, so sign-ins and handoffs are untouched. The launcher becomes “Claude (new name)”, so drag it to the Dock again.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var badgeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CommitField(value: p.badgeImage == nil ? p.badge : "",
                            placeholder: p.badgeImage == nil ? "Initial" : "Image", commit: saveBadge).frame(width: 120)
                Button(p.badgeImage == nil ? "Choose Image…" : "Change Image…") { chooseImage() }
            }
            HStack(spacing: 8) {
                ForEach(palette, id: \.1) { name, hex in
                    let on = hex.caseInsensitiveCompare(p.color) == .orderedSame
                    Button { app?.cli(["app", p.id, "--color", hex]) } label: {
                        Circle().fill(Color(nsColor: NSColor(hex: hex))).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary, lineWidth: on ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain).help(name)
                }
            }
            Text(p.isDefault ? "The default account is Claude.app itself, so its badge shows here and in the menu bar only."
                             : "One or two letters in any script, or one emoji. Clear it to go back to the initial. The launcher is rebuilt with it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var dockBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show the badge on the running app’s Dock icon", isOn: Binding(
                get: { p.dockIcon ?? false },
                set: { on in app?.cli(["app", p.id, on ? "--dock-icon" : "--no-dock-icon"]) }))
            if p.open { Text("Takes effect the next time \(p.name) opens.").font(.caption).foregroundStyle(.secondary) }
            Divider()
            if let l = p.launcher {
                HStack {
                    if dockPinned(l) {
                        Label("The launcher is in the Dock", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("The launcher isn’t in the Dock", systemImage: "dock.rectangle").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show Launcher in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: l)]) }
                }
            } else {
                HStack {
                    Text("No launcher yet.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Make Launcher") { app?.cli(["app", p.id]) }
                }
            }
            Text("Drag the launcher to the Dock to open \(p.name) from there. Don’t use Keep in Dock on the running Claude: that icon opens your default account. While \(p.name) runs, it shows as a second icon beside the launcher.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for \(p.name)’s badge"
        if panel.runModal() == .OK, let url = panel.url { app?.cli(["app", p.id, "--badge-image", url.path]) }
    }
}

func validName(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    return !t.isEmpty && t.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        && !["default", "3p", "3P"].contains(t)
}

// MARK: get started

struct GetStartedView: View {
    @ObservedObject var store: Store
    @AppStorage("skillAdded") private var skillAdded = false
    @ViewState private var loginOn = SMAppService.mainApp.status == .enabled

    var app: App? { store.app }

    var body: some View {
        let p = store.second
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: tandemLogo(height: 44))
                    Text("A second Claude account beside your first, and a way to hand work between them.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                Step(done: FileManager.default.fileExists(atPath: "/Applications/Claude.app"),
                     title: "Claude is installed",
                     detail: "Every profile runs the one Claude.app in /Applications — Tandem never changes it.") {
                    EmptyView()
                }
                Step(done: p != nil,
                     title: p.map { "A profile for your second account: \($0.name)" } ?? "Make a profile for your second account",
                     detail: "Its own sign-ins for Claude and Claude Code. Skills, settings and CLAUDE.md stay shared.") {
                    if p == nil { Button("New Profile…") { store.showNewProfile = true } }
                }
                Step(done: p?.desktopAccount != nil,
                     title: "Sign in to Claude as \(p?.name ?? "it")",
                     detail: "When claude.ai opens to sign in, copy the link into a private browser window. Otherwise it signs the new profile into the account your browser already has.") {
                    if let p, p.desktopAccount == nil {
                        Button("Open Claude as \(p.name)") { app?.cli(["desktop", p.id]) { self.app?.watchForSignIn(p.id) } }
                    }
                }
                Step(done: p?.email != nil,
                     title: "Sign in to Claude Code as \(p?.name ?? "it")",
                     detail: "Once, in Terminal. Afterwards Claude’s Code tab and Claude Code in a terminal share that sign-in.") {
                    if let p, p.email == nil { Button("Open Claude Code") { app?.openCode(p.id, name: p.name) } }
                }
                Step(done: p?.launcher.map(dockPinned) ?? false,
                     title: "Put \(p?.name ?? "its")’s launcher in the Dock",
                     detail: "Drag “Claude (\(p?.name ?? "name"))” from ~/Applications to the Dock. Pin the launcher, not the running app — that icon opens your default account.") {
                    if let l = p?.launcher, !dockPinned(l) {
                        Button("Show Launcher in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: l)]) }
                    }
                }
                Step(done: skillAdded,
                     title: "Add the /handoff skill — for handing projects over",
                     detail: "In Claude › Settings › Skills › Add, once in each account you hand work from. Skip it if you only want two accounts side by side.") {
                    if !skillAdded {
                        Button("Show Skill File") { app?.showSkill() }
                        Button("Done") { skillAdded = true }
                    }
                }
                Step(done: loginOn,
                     title: "Open Claude Tandem at login",
                     detail: "Keeps the menu bar switcher there after a restart.") {
                    if !loginOn { Button("Turn On") { app?.toggleLogin(); loginOn = SMAppService.mainApp.status == .enabled } }
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }
}

struct Step<Actions: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2).foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(done ? .secondary : .primary)
                if !done {
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { actions() }.padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: new profile

struct NewProfileSheet: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var color = palette[0].1
    @ViewState private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New profile").font(.title2.bold())
            Text("A second identity for Claude and Claude Code, in its own folders. Letters, digits, - and _ — you can rename it later.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name, e.g. work", text: $name).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                ForEach(palette, id: \.1) { label, hex in
                    Button { color = hex } label: {
                        Circle().fill(Color(nsColor: NSColor(hex: hex))).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary, lineWidth: color == hex ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain).help(label)
                }
            }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!validName(name) || working
                              || store.profiles.contains { $0.id.caseInsensitiveCompare(name) == .orderedSame || $0.name == name })
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        working = true
        store.app?.cli(["create", n], onFail: { working = false }, then: {
            store.app?.cli(["app", n, "--color", color], onFail: { working = false }, then: {
                working = false
                store.selection = "setup"
                store.refresh()
                dismiss()
            })
        })
    }
}

// MARK: the logo, in colour — the window's header and the app icon

// assets/gen-logo.py's LOGO: a = the stoker, b = the captain, # = the bike
let logoSprite = [
    ".......aaaaaaaaaaaa.....bbbbbbbbbbbb.........",
    ".......aa.aaaaaa.aa.....bb.bbbbbb.bb.........",
    ".....aaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbb##......",
    ".......aaaaaaaaaaaa.....bbbbbbbbbbbb..#......",
    "........a.a....a.a.......b.b....b.b...#......",
    "......#################################......",
    "......#...............................#......",
    "...#######.........................#######...",
    ".##...#...##.....................##...#...##.",
    "##....#....##...................##....#....##",
    "#.....#.....#...................#.....#.....#",
    "##.........##...................##.........##",
    ".##.......##.....................##.......##.",
    "...#######.........................#######...",
]
let logoColors: [Character: String] = ["a": "#B4572A", "b": "#D9773F", "#": "#8A7F76"]

func drawLogo(in r: NSRect) {
    let cols = CGFloat(logoSprite[0].count), rows = CGFloat(logoSprite.count)
    let bw = r.width / cols, bh = r.height / rows
    // Blocks, not shapes: without this, each block's soft edge shows as a hairline grid.
    let ctx = NSGraphicsContext.current, aa = ctx?.shouldAntialias ?? true
    ctx?.shouldAntialias = false
    defer { ctx?.shouldAntialias = aa }
    for (j, row) in logoSprite.enumerated() {
        for (i, ch) in row.enumerated() {
            guard let hex = logoColors[ch] else { continue }
            NSColor(hex: hex).setFill()
            // flipped drawing: row 0 at the top
            NSRect(x: r.minX + CGFloat(i) * bw, y: r.minY + CGFloat(j) * bh, width: bw + 0.3, height: bh + 0.3).fill()
        }
    }
}

/// Blocks keep Clawd's proportions: 3 wide by 5.6 tall.
func tandemLogo(height: CGFloat) -> NSImage {
    let w = height * (CGFloat(logoSprite[0].count) * 3.0) / (CGFloat(logoSprite.count) * 5.6)
    return NSImage(size: NSSize(width: w, height: height), flipped: true) { r in drawLogo(in: r); return true }
}

/// The app icon: the logo on a cream tile, on Apple's icon grid (824 of 1024, corner radius 185).
func tandemAppIcon() -> NSImage {
    NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        NSColor(hex: "#F6F0E6").setFill()
        NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
        let lw: CGFloat = 660
        let lh = lw * (CGFloat(logoSprite.count) * 5.6) / (CGFloat(logoSprite[0].count) * 3.0)
        drawLogo(in: NSRect(x: 512 - lw / 2, y: 512 - lh / 2, width: lw, height: lh))
        return true
    }
}

/// The app icon at every size an .icns holds, as PNGs in an .iconset folder for iconutil.
/// `tandem menubar` runs `ClaudeTandem --write-iconset <dir>` while it builds the bundle.
func writeIconset(to dir: String) -> Bool {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let icon = tandemAppIcon()
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
            rep.size = NSSize(width: px, height: px)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = px < 128 ? .none : .high
            icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
            guard let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: URL(fileURLWithPath: dir + "/" + name))) != nil else { return false }
        }
    }
    return true
}

// MARK: a field that saves when editing ends

/// A text field that hands its value to `commit` when editing ends — Return, Tab, or a
/// click elsewhere — the way a Mac settings field saves, with no Save button. If `commit`
/// refuses the value, the field goes back to `value`. Only typing counts: a field that was
/// merely focused never saves, and keeps showing the current value as it changes elsewhere
/// (otherwise it could save stale text over a rename made in the menu or the CLI).
struct CommitField: NSViewRepresentable {
    let value: String
    let placeholder: String
    let commit: (String) -> Bool

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.delegate = context.coordinator
        f.bezelStyle = .roundedBezel
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        f.placeholderString = placeholder
        if !context.coordinator.typed, f.stringValue != value { f.stringValue = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommitField
        var typed = false
        init(_ p: CommitField) { parent = p }

        func controlTextDidChange(_ n: Notification) { typed = true }

        func controlTextDidEndEditing(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            defer { typed = false }
            guard typed else { f.stringValue = parent.value; return }
            if f.stringValue != parent.value, !parent.commit(f.stringValue) { f.stringValue = parent.value }
        }

        // Escape puts the saved value back instead of saving what was typed. Tab ends
        // editing too: in a SwiftUI window there's often no next field for it to move to.
        func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard let f = c as? NSTextField else { return false }
            switch sel {
            case #selector(NSResponder.cancelOperation(_:)):
                typed = false
                f.stringValue = parent.value
                f.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                f.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

// MARK: settings — its own window (App.showSettings), one form per tab

/// An ⓘ that shows the longer explanation in a popover, so the form itself stays short.
struct InfoButton: View {
    let text: String
    @ViewState private var shown = false
    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .help(text).accessibilityLabel("About this setting")
            .popover(isPresented: $shown, arrowEdge: .trailing) {
                Text(text).fixedSize(horizontal: false, vertical: true).frame(width: 280).padding(14)
            }
    }
}

struct HandoffsSettings: View {
    @ObservedObject var store: Store
    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { store.config["on-arrival"] ?? "ask" }, set: { store.setConfig("on-arrival", $0) })) {
                    Text("Ask Me").tag("ask")
                    Text("Receive Automatically").tag("auto")
                    Text("Only Show It in Handoffs").tag("off")
                } label: {
                    HStack { Text("When a handoff arrives"); InfoButton(text: "Receiving verifies every file before it claims the project. If that profile’s Claude is open, the steps that need it closed wait until it quits, then finish on their own.") }
                }
                Picker(selection: Binding(get: { store.config["on-brief"] ?? "ask" }, set: { store.setConfig("on-brief", $0) })) {
                    Text("Ask Before Sending").tag("ask")
                    Text("Send Automatically").tag("auto")
                } label: {
                    HStack { Text("When /handoff writes a brief"); InfoButton(text: "/handoff leaves a note saying where the brief is going. Sending automatically only happens when that names a profile or Mac Tandem knows.") }
                }
            } footer: {
                Text("The same settings tandem watch follows on a Mac without the app.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 520).fixedSize()
        .onAppear { store.loadConfig() }
    }
}

struct GeneralSettings: View {
    @ObservedObject var store: Store
    @AppStorage("terminal") private var terminal = ""
    @ViewState private var loginOn = SMAppService.mainApp.status == .enabled
    var body: some View {
        let ghostty = store.app?.ghosttyInstalled ?? false
        Form {
            Toggle(isOn: Binding(get: { loginOn }, set: { _ in store.app?.toggleLogin(); loginOn = SMAppService.mainApp.status == .enabled })) {
                HStack { Text("Open Claude Tandem at login"); InfoButton(text: "Leave it on: Tandem only hears about handoffs, and publishes the card that shows this Mac on your other Mac, while it runs.") }
            }
            Picker(selection: Binding(get: { store.app?.terminalApp ?? "Terminal" }, set: { terminal = $0 })) {
                Text("Terminal").tag("Terminal")
                if ghostty { Text("Ghostty").tag("Ghostty") }
            } label: {
                HStack { Text("Open Claude Code in")
                    InfoButton(text: ghostty ? "Ghostty opens a new window in the Ghostty you already have open. The first time, macOS asks whether Claude Tandem may control it."
                                             : "Install Ghostty to use it here.") }
            }
        }
        .formStyle(.grouped).frame(width: 520).fixedSize()
    }
}

struct MaintenanceSettings: View {
    @ObservedObject var store: Store
    var body: some View {
        Form {
            Section {
                row("Run Doctor", "The shared drive, iCloud, the engine, folder links, and whether this Claude still works with profiles. Changes nothing.", ["doctor"], "tandem doctor")
                row("Sync Claude Code Sessions", "Copies sessions between profiles, so /resume finds them anywhere.", ["profile", "sync"], "tandem profile sync")
                row("Find Conflict Copies", "iCloud’s “name 2” copies in the shared tree. Reports only.", ["conflicts"], "tandem conflicts")
                row("Update the Shared Engine", "Puts this version’s engine on the shared drive, for every Mac.", ["deploy"], "tandem deploy")
            }
        }
        .formStyle(.grouped).frame(width: 520).fixedSize()
        .sheet(item: $store.settingsLogJob) { job in LogSheet(job: job) }
    }

    func row(_ title: String, _ help: String, _ args: [String], _ cli: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Run") { store.runLog(title, args, inSettings: true) }.help(cli)
        }
    }
}

/// Output of a maintenance step, in place of a terminal window.
struct LogSheet: View {
    @ObservedObject var job: Job
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if job.running { ProgressView().controlSize(.small) }
                else { Image(systemName: job.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(job.ok ? .green : .orange) }
                Text(job.title).font(.title3.bold())
            }
            ScrollView {
                Text(job.log.isEmpty ? "…" : job.log).font(.callout.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 360)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(job.running) }
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// A profile's shared projects: what it holds, what's coming to it, what's waiting.
struct ProfileProjects: View {
    @ObservedObject var store: Store
    let p: Profile
    var side: String { store.app?.side(p) ?? p.id }

    var body: some View {
        let all = store.ledger?.projects ?? []
        let held = all.filter { $0.holder == side && $0.state == "held" }
        let coming = all.filter { $0.holder == side && $0.state == "sent" }
        let away = all.filter { $0.state == "sent" && $0.last?.machine == side }
        VStack(alignment: .leading, spacing: 8) {
            if store.ledger == nil { Text("Reading the shared drive…").foregroundStyle(.secondary) }
            else if held.isEmpty && coming.isEmpty && away.isEmpty && store.heldHere(side).isEmpty {
                Text("Holds no shared project. Projects come here when they’re handed to \(p.name), and leave with Hand Off.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(coming) { x in
                HStack {
                    Label(x.name, systemImage: "arrow.down.circle.fill").foregroundStyle(.green)
                    Text("from \(store.label(x.last?.machine ?? "")) · \(ago(x.last?.at))").foregroundStyle(.secondary)
                    Spacer()
                    Button("Receive") { store.startReceive(x.name, as: side) }.disabled(store.running("receive", x.name))
                }
            }
            ForEach(held) { x in
                HStack {
                    Label(x.name, systemImage: "folder.fill")
                    if !x.intents.isEmpty { Text("brief ready").font(.caption).foregroundStyle(.blue) }
                    if !x.requests.isEmpty { Text("asked for").font(.caption).foregroundStyle(.purple) }
                    Spacer()
                    Button("Hand Off…") { store.selection = "handoffs"; store.draft(x.name, from: side) }
                }
            }
            ForEach(store.heldHere(side), id: \.self) { name in
                HStack {
                    Label(name, systemImage: "lock.fill").foregroundStyle(.secondary)
                    Text("locked here since it was handed away").foregroundStyle(.secondary)
                    Spacer()
                    Button("Unlock") { store.runLog("Unlock \(name) for \(p.name)", store.profileArgs(side) + ["release", name]) }
                        .help(p.open ? "Quit \(p.name)’s Claude first — unlocking edits its project list" : "tandem release")
                }
            }
            ForEach(away) { x in
                HStack {
                    Label(x.name, systemImage: "paperplane").foregroundStyle(.secondary)
                    Text("sent to \(store.label(x.holder ?? "")) · not received yet").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}
