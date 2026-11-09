// Projects: every project Tandem can see, on a grid of the places it can be.
//
// A place is one profile's Claude on one Mac (a "side": Madoka, Madoka@Junipera, Ji-su, …).
// Columns are places, grouped by profile name, this Mac first in each group; rows are
// projects. A cell says what that place has: the project itself, an old copy, or the
// project on its way. A flat list showed the total but not where anything was, and a menu
// of "Ask for It as Personal" didn't say from which Mac (2026-11-08); here every project
// has one next step, named by the place it goes to. Projects that exist only on claude.ai
// aren't listed: Tandem has no way to read them, and they are on every Mac already.
import AppKit
import SwiftUI

// MARK: model

struct Place: Identifiable, Hashable {
    let side: String, mac: String, name: String, color: String?, here: Bool
    var id: String { side }
}

struct PlaceGroup: Identifiable {
    let name: String, color: String?, places: [Place]
    var id: String { name }
}

/// One row: a shared project, or a project defined in one place only.
struct PRow: Identifiable, Hashable {
    let name: String
    let shared: Bool
    let side: String?            // the one place, for a project that isn't shared
    var id: String { shared ? name : "\(name)\u{1}\(side ?? "")" }
}

enum CellState { case none, holds, coming, copy, only }

extension Store {
    /// Every place, this Mac first, then the others by name. A Mac without a card (an older
    /// Tandem) gives only side names: its default profile takes this Mac's default profile's
    /// name, any other the profile id, so it lands in the right column group.
    var places: [Place] {
        let ms = (ledger?.machines ?? []).sorted { ($0.this == true ? 0 : 1, $0.mac) < ($1.this == true ? 0 : 1, $1.mac) }
        let named = ms.flatMap(\.sides).filter { $0.name != nil }
        func fallback(_ s: MSide) -> (String, String?) {
            let prof = s.profile ?? (s.side.contains("@") ? String(s.side.split(separator: "@")[1]) : "default")
            let twin = named.first { ($0.profile ?? "") == prof }
            return (twin?.name ?? prof, twin?.color)
        }
        return ms.flatMap { m in
            m.sides.map { s in
                let f = s.name == nil ? fallback(s) : (s.name!, s.color)
                return Place(side: s.side, mac: m.mac, name: f.0, color: s.color ?? f.1, here: m.this == true)
            }
        }
    }

    /// Places grouped by profile name, the default profile's group first.
    var placeGroups: [PlaceGroup] {
        let all = places
        var names: [String] = []
        for p in all where !names.contains(p.name) { names.append(p.name) }
        let defaults = Set(all.filter { !$0.side.contains("@") }.map(\.name))
        names.sort { (defaults.contains($0) ? 0 : 1) < (defaults.contains($1) ? 0 : 1) }
        return names.map { n in
            let ps = all.filter { $0.name == n }
            return PlaceGroup(name: n, color: ps.first(where: \.here)?.color ?? ps.first?.color, places: ps)
        }
    }

    var projectRows: [PRow] {
        let shared = (ledger?.projects ?? []).map { PRow(name: $0.name, shared: true, side: nil) }
        let local = (ledger?.unshared ?? []).map { PRow(name: $0.project, shared: false, side: $0.side) }
        return shared + local
    }

    func shared(_ r: PRow) -> LProject? { r.shared ? ledger?.projects.first { $0.name == r.name } : nil }

    /// Places whose Claude defines the project, on any Mac.
    func definers(_ project: String) -> [String] {
        (ledger?.machines ?? []).flatMap { $0.sides.filter { $0.projects?.contains(project) ?? false }.map(\.side) }
    }

    func cell(_ r: PRow, _ side: String) -> CellState {
        guard r.shared else { return r.side == side ? .only : .none }
        let p = shared(r)
        if home(r) == side { return p?.state == "sent" ? .coming : .holds }
        return definers(r.name).contains(side) ? .copy : .none
    }

    /// Where the project is now: its holder, or its one place.
    /// A project just shared has no handoff recorded yet: the one place that has it holds it.
    func home(_ r: PRow) -> String? {
        guard r.shared else { return r.side }
        if let h = shared(r)?.holder { return h }
        let d = definers(r.name)
        return d.count == 1 ? d[0] : nil
    }

    func place(_ side: String?) -> Place? { places.first { $0.side == side } }
    func placeLabel(_ side: String?) -> String {
        guard let pl = place(side) else { return side ?? "" }
        return "\(pl.mac) · \(pl.name)"
    }

    /// The place on this Mac a project should come to: the profile with the same name as
    /// where it is now, else the default profile.
    func bringTarget(_ r: PRow) -> String? {
        let from = place(home(r))?.name
        let mine = places.filter(\.here)
        return (mine.first { $0.name == from } ?? mine.first { !$0.side.contains("@") } ?? mine.first)?.side
    }

    /// Dropping a project's dot on another place: hand it off from here, or ask for it.
    /// A project only on this Mac is shared first, then handed off.
    func move(_ r: PRow, to side: String) {
        guard let from = home(r), from != side else { return }
        if !r.shared {
            if isMine(from) { share(r.name, as: from) { self.draft(r.name, from: from, to: side) } }
        } else if isMine(from) { draft(r.name, from: from, to: side) }
        else if isMine(side) { ask(r.name, as: side) }
    }

    /// Whether a drop on this place does something, so only those cells light up.
    func canMove(_ r: PRow, to side: String) -> Bool {
        guard let from = home(r), from != side else { return false }
        return isMine(from) || (r.shared && isMine(side))
    }
}

func hexColor(_ hex: String?) -> Color { hex.map { Color(nsColor: NSColor(hex: $0)) } ?? .secondary }

// MARK: the page

struct ProjectsView: View {
    @ObservedObject var store: Store
    @ViewState private var group = "kind"
    @ViewState private var selected: String?
    @ViewState private var grewBy: CGFloat = 0

    static let col: CGFloat = 56

    /// The name column fits the longest name (capped; longer ones truncate with a tooltip),
    /// so the dots sit right beside the names instead of at the far edge of the window.
    static func nameWidth(_ rows: [PRow]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = rows.map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 120
        return min(max(ceil(widest), 120), 260) + 18 + 8 + 4   // + icon, spacing, slack
    }

    var body: some View {
        let rows = store.projectRows
        let nameWidth = Self.nameWidth(rows)
        // A List, so selection, arrow keys and VoiceOver work like Finder's; the column
        // titles and the legend are rows too, so they share the rows' insets and line up.
        List(selection: $selected) {
            Section { header(nameWidth).selectionDisabled() }
            if store.ledger == nil {
                Text("Reading the shared drive…").foregroundStyle(.secondary).selectionDisabled()
            } else if rows.isEmpty {
                Text("No projects yet. Make one in Claude, then share it to hand it off.").foregroundStyle(.secondary).selectionDisabled()
            }
            ForEach(sections(rows), id: \.0) { title, list in
                Section("\(title) · \(list.count)") {
                    ForEach(list) { r in ProjectGridRow(store: store, r: r, nameWidth: nameWidth).tag(r.id) }
                }
            }
            Section { legend.padding(.top, 8).selectionDisabled() }
        }
        .listStyle(.inset)
        // The inspector adds its minimum width to the window's minimum on top of the
        // grid's, open or closed (measured: closed, 1028 pt = sidebar + grid + 260; open,
        // its own width again on top). So the grid asks for that much less, and the window
        // fits the sidebar and grid, plus the panel's width only while it's open.
        .frame(minWidth: gridWidth(nameWidth) - Self.inspectorMin)
        .navigationSubtitle(subtitle(rows))
        .toolbar {
            // Finder's Group By: a menu button, so the toolbar stays one group of icons
            ToolbarItem {
                Menu {
                    Picker("Group By", selection: $group) {
                        Text("Kind").tag("kind")
                        Text("Where It Is").tag("where")
                        Text("Profile").tag("profile")
                    }
                    .pickerStyle(.inline)
                } label: { Label("Group By", systemImage: "rectangle.3.group") }
                .help("Group the projects by kind, by the Mac they’re on, or by profile")
            }
            ToolbarItem(placement: .primaryAction) { CheckNowButton(store: store) }
        }
        // Opening the inspector makes SwiftUI widen the window by about twice the panel's
        // width. Trim it to the panel's own width, and give that back when it closes, so
        // selecting and deselecting doesn't ratchet the window wider each time.
        .onChange(of: selected != nil) { wasOpen, open in
            guard open != wasOpen, let w = store.app?.window else { return }
            let before = w.frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                var f = w.frame
                if open {
                    let want = before.width + Self.inspectorIdeal
                    if f.width > want { f.size.width = want }
                    grewBy = f.width - before.width
                } else if grewBy > 0 {
                    f.size.width = max(f.width - grewBy, w.minSize.width)
                    grewBy = 0
                }
                if f != w.frame { w.setFrame(f, display: true, animate: true) }
            }
        }
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Group {
                if let r = rows.first(where: { $0.id == selected }) { ProjectInspector(store: store, r: r) }
                else { Text("Select a project").foregroundStyle(.secondary) }
            }
            .inspectorColumnWidth(min: Self.inspectorMin, ideal: Self.inspectorIdeal, max: 360)
        }
    }

    static let inspectorMin: CGFloat = 260, inspectorIdeal: CGFloat = 290

    /// Names, every place's column, the groups' padding, and the list's insets.
    func gridWidth(_ nameWidth: CGFloat) -> CGFloat {
        nameWidth + Self.col * CGFloat(max(store.places.count, 2)) + 4 * CGFloat(store.placeGroups.count) + 40
    }

    func subtitle(_ rows: [PRow]) -> String {
        let s = rows.filter(\.shared).count
        return "\(rows.count) project\(rows.count == 1 ? "" : "s") · \(s) shared · \(rows.count - s) on one Mac"
    }

    func sections(_ rows: [PRow]) -> [(String, [PRow])] {
        let sorted = rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        func keep(_ t: String, _ f: (PRow) -> Bool) -> (String, [PRow])? {
            let l = sorted.filter(f); return l.isEmpty ? nil : (t, l)
        }
        switch group {
        case "where":
            let macs = store.places.map(\.mac).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return macs.compactMap { m in keep("On \(m)") { store.place(store.home($0))?.mac == m } }
                + [keep("Not recorded") { store.home($0) == nil }].compactMap { $0 }
        case "profile":
            return store.placeGroups.compactMap { g in keep(g.name) { store.place(store.home($0))?.name == g.name } }
                + [keep("Not recorded") { store.home($0) == nil }].compactMap { $0 }
        default:
            return [keep("Shared · moves between places", \.shared), keep("Only on one Mac") { !$0.shared }].compactMap { $0 }
        }
    }

    /// Profile names over their columns, then each column's Mac.
    func header(_ nameWidth: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Color.clear.frame(width: nameWidth, height: 1)
            ForEach(store.placeGroups) { g in
                VStack(spacing: 4) {
                    Text(g.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Rectangle().fill(hexColor(g.color)).frame(width: Self.col * CGFloat(g.places.count), height: 2)
                    HStack(spacing: 0) {
                        ForEach(g.places) { pl in
                            Text(pl.mac).font(.caption).foregroundStyle(pl.here ? Color.accentColor : .secondary)
                                .frame(width: Self.col).help(pl.here ? "\(pl.mac) · \(pl.name) — this Mac" : "\(pl.mac) · \(pl.name)")
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            Spacer(minLength: 0)
        }
    }

    var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                legendItem(.holds, "Has it"); legendItem(.coming, "On its way")
                legendItem(.copy, "Old copy, locked"); legendItem(.only, "Only here")
            }
            Text("Drag a project’s mark to another profile or Mac to move it there. A project only on this Mac is shared first.").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Projects that exist only on claude.ai aren’t listed: they’re on every Mac signed in to that account already.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                InfoButton(text: "Tandem lists the Claude projects stored on a Mac, the ones a handoff moves. A project made on claude.ai or in the Claude app on your phone lives on Anthropic’s servers, so Claude shows it wherever that account is signed in. Tandem can’t read that list.")
            }
        }
        .font(.caption)
    }

    func legendItem(_ s: CellState, _ t: String) -> some View {
        HStack(spacing: 5) { CellMark(state: s, tint: .secondary); Text(t).foregroundStyle(.secondary) }
    }
}

// MARK: a row

struct ProjectGridRow: View {
    @ObservedObject var store: Store
    let r: PRow
    let nameWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: r.shared ? "folder" : "desktopcomputer").foregroundStyle(.secondary).frame(width: 18)
                Text(r.name).lineLimit(1).truncationMode(.tail).help(r.name)
            }
            .frame(width: nameWidth, alignment: .leading)
            ForEach(store.placeGroups) { g in
                HStack(spacing: 0) {
                    ForEach(g.places) { pl in PlaceCell(store: store, r: r, place: pl, width: ProjectsView.col, height: 26) }
                }
                .padding(.horizontal, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contextMenu { ProjectActions(store: store, r: r, menu: true) }
    }
}

/// One place's cell for one project. The dot can be dragged to another place's cell to
/// hand the project off from here or to ask for it here.
struct PlaceCell: View {
    @ObservedObject var store: Store
    let r: PRow
    let place: Place
    let width: CGFloat, height: CGFloat
    var caption = false
    @ViewState private var targeted = false

    var body: some View {
        let s = store.cell(r, place.side)
        let canDrag = (s == .holds || s == .coming || (s == .only && store.isMine(place.side))) && store.home(r) == place.side
        let cell = ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(targeted ? Color.accentColor.opacity(0.25) : place.here ? Color.accentColor.opacity(0.05) : .clear)
            VStack(spacing: 3) {
                CellMark(state: s, tint: hexColor(place.color))
                if caption { Text(captionText(s)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        Group {
            // The whole cell is the handle, not just the 12 pt mark inside it.
            if canDrag {
                cell.draggable(r.name) {
                    Label(r.name, systemImage: r.shared ? "folder" : "desktopcomputer")
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                }
                .help("Drag to another profile or Mac to \(!r.shared ? "share it and hand it off" : store.isMine(place.side) ? "hand it off" : "ask for it")")
            } else {
                cell
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.mac) · \(place.name): \(captionText(s).isEmpty ? "not here" : captionText(s))")
        .dropDestination(for: String.self) { items, _ in
            guard items.first == r.name, store.canMove(r, to: place.side) else { return false }
            store.move(r, to: place.side); return true
        } isTargeted: { t in targeted = t && store.canMove(r, to: place.side) }
    }

    func captionText(_ s: CellState) -> String {
        switch s {
        case .holds: return "has it"
        case .coming: return "on its way"
        case .copy: return "old copy"
        case .only: return "only here"
        case .none: return ""
        }
    }
}

struct CellMark: View {
    let state: CellState
    let tint: Color
    var body: some View {
        switch state {
        case .holds: Circle().fill(tint).frame(width: 12, height: 12)
        case .coming: Image(systemName: "arrow.right.circle.fill").foregroundStyle(tint).font(.system(size: 13))
        case .copy: Circle().strokeBorder(tint.opacity(0.6), lineWidth: 2).frame(width: 12, height: 12)
        case .only: RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 12, height: 12)
        case .none: Color.clear.frame(width: 12, height: 12)
        }
    }
}

// MARK: actions

extension Store {
    /// One line on where a project is, from this Mac's point of view.
    func status(_ r: PRow) -> String {
        guard r.shared else {
            return isMine(r.side) ? "Only in \(placeLabel(r.side)). Share it to hand it off: its folder moves to the shared drive, checked file by file, and the original is kept aside."
                                  : "Only in \(placeLabel(r.side)). Share it from \(place(r.side)?.mac ?? "that Mac") to hand it off."
        }
        guard let p = shared(r) else { return "" }
        let at = ago(p.last?.at)
        switch p.state {
        case "held": return isMine(p.holder) ? "\(placeLabel(p.holder)) has it, since \(at)." : "\(placeLabel(p.holder)) has it, since \(at). Bringing it here asks that Mac to send it."
        case "sent": return "On its way to \(placeLabel(p.holder)), sent \(at)."
        case "unreadable": return "Its newest ownership record is on the drive but hasn’t downloaded yet."
        default:
            if let h = home(r) { return "Shared from \(placeLabel(h)). Hand it off to move it to another Mac or account." }
            return "No handoff recorded yet."
        }
    }
}

extension Store {
    /// Copies a project's folder into the shared drive and switches the project to the copy.
    /// The switch edits spaces.json, which a running Claude rewrites from memory, so that
    /// profile's Claude has to be closed. Quitting it takes away whatever is on screen, so
    /// ask first, and open it again afterwards — also when sharing failed.
    func share(_ project: String, as side: String, then: (() -> Void)? = nil) {
        guard let p = profile(forSide: side) else { return }
        let go = { (reopen: Bool) in
            let job = Job(kind: "log", title: "Share \(project)")
            // with a next step, the log sheet would sit in front of it: show the log only alone
            if then == nil { self.logJob = job }
            self.run(job, self.profileArgs(side) + ["migrate", project]) { j in
                if reopen, let now = self.profile(forSide: side) { self.app?.openDesktop(now) }
                if j.code != 0 { self.logJob = j } else { then?() }
            }
        }
        guard p.open else { go(false); return }
        let a = NSAlert()
        a.messageText = "Quit Claude (\(p.name)) to share “\(project)”?"
        a.informativeText = "Sharing copies the project’s folder to the shared drive and switches the project to the copy, so either Mac can work on it. Claude has to be closed for the switch. It opens again when sharing is done."
            + (then == nil ? "" : " Then you write the note for the handoff.")
        a.addButton(withTitle: "Quit Claude and Share")
        a.addButton(withTitle: "Cancel")
        let answer = { (r: NSApplication.ModalResponse) in
            if r == .alertFirstButtonReturn { self.app?.cli(["quit", p.id]) { go(true) } }
        }
        // After the current event, never during it: a modal started while a drop is still
        // being delivered returns at once, as if the user had said no.
        DispatchQueue.main.async {
            if let w = self.app?.window, w.isVisible { a.beginSheetModal(for: w, completionHandler: answer) }
            else { answer(a.runModal()) }
        }
    }
}

/// The next steps for a project: the primary one first. Used by the inspector's buttons
/// and by the row's right-click menu.
struct ProjectActions: View {
    @ObservedObject var store: Store
    let r: PRow
    let menu: Bool

    var body: some View {
        let p = store.shared(r)
        let home = store.home(r)
        let mine = store.places.filter(\.here)
        if r.shared {
            if let h = home, store.isMine(h), p?.state == "sent" {
                Button("Receive") { store.selection = "handoffs"; store.startReceive(r.name, as: h) }
            } else if let h = home ?? store.definers(r.name).first(where: store.isMine), store.isMine(h) {
                Button("Hand Off…") { store.draft(r.name, from: h) }
            } else if let t = store.bringTarget(r) {
                Button("Bring to \(store.placeLabel(t))") { store.ask(r.name, as: t) }
                ForEach(mine.filter { $0.side != t }) { pl in
                    Button("Bring to \(pl.mac) · \(pl.name)") { store.ask(r.name, as: pl.side) }
                        .help("Another profile, so another account: the project moves to it")
                }
            }
        } else if let s = r.side, store.isMine(s) {
            Button("Share") { store.share(r.name, as: s) }
        }
        if menu {
            Divider()
            secondary(p)
        }
    }

    @ViewBuilder func secondary(_ p: LProject?) -> some View {
        let here = (r.shared ? store.definers(r.name) : [r.side].compactMap { $0 }).filter(store.isMine)
        ForEach(here, id: \.self) { s in
            Button(here.count > 1 ? "Open in Claude as \(store.place(s)?.name ?? s)" : "Open in Claude") {
                if r.shared { store.openInClaude(r.name, as: s) }
                else if let pr = store.profile(forSide: s) { store.app?.openDesktop(pr) }
            }
        }
        if let p {
            Button("History…") { store.runLog("History of \(p.name)", ["log", p.name]) }
            Button("Show in the Shared Drive") { store.showInFinder(p.name) }
            if let d = p.doc?.name, let root = store.ledger?.root {
                Button("Open the Newest Brief") { NSWorkspace.shared.open(URL(fileURLWithPath: "\(root)/Projects/\(p.name)/\(d)")) }
            }
            ForEach(store.mySides.filter { store.heldHere($0).contains(p.name) }, id: \.self) { s in
                Button("Unlock It for \(store.label(s))") { store.runLog("Unlock \(p.name)", store.profileArgs(s) + ["release", p.name]) }
            }
        }
    }
}

// MARK: the inspector

struct ProjectInspector: View {
    @ObservedObject var store: Store
    let r: PRow

    var body: some View {
        let p = store.shared(r)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(r.shared ? "Shared" : "Only on \(store.place(r.side)?.mac ?? "one Mac")")
                        .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                section("Where it is") { miniGrid }
                Text(store.status(r)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ProjectActions(store: store, r: r, menu: false)
                }
                .buttonStyle(.bordered).controlSize(.regular)
                if let n = p?.last?.note, !n.isEmpty {
                    Text("“\(n)”").font(.callout).italic().fixedSize(horizontal: false, vertical: true)
                }
                if let h = p?.history, !h.isEmpty {
                    section("History") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(h.suffix(6).reversed().enumerated()), id: \.offset) { _, e in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(ago(e.at)).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                                    Text("\(verb(e.verb)) \(store.placeLabel(e.side))").fixedSize(horizontal: false, vertical: true)
                                }.font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func verb(_ v: String) -> String {
        switch v {
        case "handoff": return "Sent by"
        case "claim", "pickup": return "Received by"
        case "release": return "Unlocked by"
        default: return v.prefix(1).uppercased() + v.dropFirst() + " ·"
        }
    }

    func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            c()
        }
    }

    /// Profiles down, Macs across; drop the dot on another cell to move it.
    var miniGrid: some View {
        let macs = store.places.map(\.mac).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                ForEach(macs, id: \.self) { m in Text(m).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(store.placeGroups) { g in
                GridRow {
                    Text(g.name).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    ForEach(macs, id: \.self) { m in
                        if let pl = g.places.first(where: { $0.mac == m }) {
                            PlaceCell(store: store, r: r, place: pl, width: 84, height: 44, caption: true)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                        } else {
                            Text("—").foregroundStyle(.tertiary).frame(width: 84, height: 44)
                        }
                    }
                }
            }
        }
    }
}


