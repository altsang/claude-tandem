// Claude Tandem's window: the profiles, a Get Started checklist, and a New Profile sheet.
//
// Like the menu, it holds no logic of its own: every change is a `tandem profile …` call
// made through App.cli, and what it shows comes from `tandem profile list --json`,
// re-read every few seconds while the window is open.
import AppKit
import ServiceManagement
import SwiftUI

// MARK: state

final class Store: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selection: String? = "setup"
    @Published var showNewProfile = false
    @Published var loaded = false
    weak var app: App?
    private var timer: Timer?
    private var loading = false

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
    w.contentMinSize = NSSize(width: 720, height: 480)
    w.contentView = NSHostingView(rootView: MainView(store: store))
    w.center()
    w.setFrameAutosaveName("ClaudeTandemMain")
    return w
}

struct MainView: View {
    @ObservedObject var store: Store

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section {
                    Label("Get Started", systemImage: "checklist").tag("setup")
                }
                Section("Profiles") {
                    ForEach(store.profiles) { p in ProfileRow(store: store, p: p).tag(p.id) }
                }
                Section {
                    Label("Settings", systemImage: "gearshape").tag("settings")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .toolbar {
                ToolbarItem {
                    Button { store.showNewProfile = true } label: { Label("New Profile", systemImage: "plus") }
                        .help("New profile")
                }
            }
        } detail: {
            if store.selection == "setup" || store.selection == nil {
                GetStartedView(store: store)
            } else if store.selection == "settings" {
                SettingsView(store: store)
            } else if let p = store.profiles.first(where: { $0.id == store.selection }) {
                ProfileDetail(store: store, p: p).id(p.id)   // fresh fields per profile
            } else if store.loaded {
                Text("That profile is gone.").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .sheet(isPresented: $store.showNewProfile) { NewProfileSheet(store: store) }
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
                Text(who(p)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if p.stale {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange).help("Reopen to update")
            } else if p.open {
                Circle().fill(.green).frame(width: 8, height: 8).help("Open")
            }
        }
        .padding(.vertical, 2)
    }
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
                header
                actions
                GroupBox("Accounts") { accounts.padding(6) }
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
                GroupBox("Name") { nameBox.padding(6) }
                GroupBox("Badge") { badgeBox.padding(6) }
                if !p.isDefault {
                    GroupBox("Dock") { dockBox.padding(6) }
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        // A click on empty space ends editing, which saves the field, as in any Mac window.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) })
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

    var header: some View {
        HStack(spacing: 16) {
            Badge(store: store, p: p, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.largeTitle.bold())
                Text(p.isDefault ? "Claude.app itself — the account you had before Tandem"
                                 : "Profile id “\(p.id)” · handoff side \(app?.side(p) ?? p.id)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            status
        }
    }

    @ViewBuilder var status: some View {
        if p.stale {
            Label("Reopen to update", systemImage: "arrow.clockwise").foregroundStyle(.orange)
        } else if p.open {
            Label("Open", systemImage: "circle.fill").foregroundStyle(.green)
        } else {
            Label("Closed", systemImage: "circle").foregroundStyle(.secondary)
        }
    }

    var actions: some View {
        HStack {
            Button(p.open ? "Show Claude" : "Open Claude") { app?.openDesktop(p) }
                .keyboardShortcut(.defaultAction)
            Button("Open Claude Code") { app?.openCode(p.id, name: p.name) }
            if p.stale {
                Button("Quit and Reopen") { app?.cli(["quit", p.id]) { self.app?.cli(["desktop", p.id]) } }
            } else if p.open {
                Button("Quit Claude") { app?.cli(["quit", p.id]) }
            }
        }
    }

    var accounts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
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
    @State private var loginOn = SMAppService.mainApp.status == .enabled

    var app: App? { store.app }

    var body: some View {
        let p = store.second
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: tandemLogo(height: 44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get started").font(.largeTitle.bold())
                        Text("A second Claude account beside your first, and a way to hand work between them.")
                            .foregroundStyle(.secondary)
                    }
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
    @State private var name = ""
    @State private var color = palette[0].1
    @State private var working = false

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

// MARK: settings

struct SettingsView: View {
    @ObservedObject var store: Store
    @AppStorage("terminal") private var terminal = ""
    @State private var loginOn = SMAppService.mainApp.status == .enabled

    var body: some View {
        let ghostty = store.app?.ghosttyInstalled ?? false
        Form {
            Picker("Open Claude Code and handoffs in", selection: Binding(
                get: { store.app?.terminalApp ?? "Terminal" }, set: { terminal = $0 })) {
                Text("Terminal").tag("Terminal")
                if ghostty { Text("Ghostty").tag("Ghostty") }
            }
            Text(ghostty ? "Ghostty opens a new window in the Ghostty you already have open. The first time, macOS asks whether Claude Tandem may control it."
                         : "Install Ghostty to use it here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Open Claude Tandem at login", isOn: Binding(
                get: { loginOn },
                set: { _ in store.app?.toggleLogin(); loginOn = SMAppService.mainApp.status == .enabled }))
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560)
        .padding()
        .navigationTitle("Settings")
    }
}
