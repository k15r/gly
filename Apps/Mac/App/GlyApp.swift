import AppKit
import SwiftUI
import GlyCore

@main
struct GlyApp: App {
    @State private var app = AppModel()
    @State private var calendars = CalendarModel()
    @State private var tasks = TasksModel()
    @State private var clock = Clock()
    @State private var nav = Navigation()
    @State private var wiki = WikiModel()
    @State private var planning = PlanningModel()
    @State private var tagColors = TagColorModel()
    @State private var meetingMarks = MeetingMarksModel()
    @State private var capture = CaptureController()
    @State private var browser = BrowserModel()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup("gly", id: "main") {
            let opener = LinkOpener(app: app, wiki: wiki, nav: nav)
            ContentView()
                .environment(app).environment(calendars).environment(tasks).environment(clock).environment(nav).environment(wiki).environment(planning)
                .environment(tagColors).environment(meetingMarks).environment(capture).environment(browser)
                .background(OpenWindowHook(capture: capture))
                .environment(\.linkOpener, opener)
                .environment(\.openURL, OpenURLAction { url in opener.open(url); return .handled })
                .frame(minWidth: 960, minHeight: 580)
                .task { await startUp() }
                .onChange(of: app.store === nil) { tasks.attach(app.store, writer: app.writer); wiki.attach(app.store); planning.attach(app.store); tagColors.attach(app.store); meetingMarks.attach(app.store) }
                .onChange(of: nav.day) { syncDay() }
                .onChange(of: clock.today) { syncDay() }
        }
        .commands {
            // Store undo/redo via the agent; while a text field is focused, the text's own undo applies (design L6).
            CommandGroup(after: .textEditing) {
                Toggle("Show Markdown Source", isOn: Binding(get: { app.showMarkdownSource }, set: { app.showMarkdownSource = $0 }))
            }
            CommandGroup(replacing: .undoRedo) {
                Button(tasks.undoLabel.map { "Undo \($0)" } ?? "Undo") { undoRedo(store: .undo, text: Selector(("undo:"))) }
                    .keyboardShortcut("z")
                Button(tasks.redoLabel.map { "Redo \($0)" } ?? "Redo") { undoRedo(store: .redo, text: Selector(("redo:"))) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            // Replaces File → New Window (single-window app), which would otherwise own ⌘N.
            CommandGroup(replacing: .newItem) {
                Button("New") { nav.requestNew() }.keyboardShortcut("n").disabled(!app.canWrite)
                Button("New Page") { nav.showNewPage = true }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!app.canWrite)
                Divider()
                Button("Quick Open…") { nav.showQuickOpen = true }.keyboardShortcut("k")
            }
            CommandMenu("Go") {
                Button("Back") { nav.back() }.keyboardShortcut("[").disabled(!nav.canGoBack)
                Button("Forward") { nav.forward() }.keyboardShortcut("]").disabled(!nav.canGoForward)
                Divider()
                Button("Previous Day") { nav.day = nav.day.adding(days: -1); nav.go(.day) }.keyboardShortcut(.leftArrow)
                Button("Next Day") { nav.day = nav.day.adding(days: 1); nav.go(.day) }.keyboardShortcut(.rightArrow)
                Button("Today") { nav.day = clock.today; nav.go(.day) }.keyboardShortcut("t")
                Divider()
                Button("Day") { nav.go(.day) }.keyboardShortcut("1")
                Button("Tasks") { nav.go(.items(ItemView.tasks.id)) }.keyboardShortcut("2")
                Button("Pages") { nav.go(.items(ItemView.pages.id)) }.keyboardShortcut("3")
                Button("Bookmarks") { nav.go(.items(ItemView.bookmarks.id)) }.keyboardShortcut("4")
                Button("All Items") { nav.go(.items(ItemView.all.id)) }.keyboardShortcut("0")
                Divider()
                Button("Save View…") { nav.saveViewRequest += 1 }.keyboardShortcut("s").disabled(!nav.showsBrowser)
            }
            CommandMenu("Developer") {
                Button("Re-check Agent") { Task { await app.refreshAgentState() } }
                Button("Unregister Agent") { Task { await app.unregisterAgent() } }
            }
        }

        Settings {
            TabView {
                AgentsSettingsView().tabItem { Label("Agents", systemImage: "cpu") }
                PlanningSettingsView().tabItem { Label("Planning", systemImage: "calendar.badge.clock") }
                CalendarListView().frame(width: 560, height: 560).tabItem { Label("Calendars", systemImage: "calendar.badge.checkmark") }
                CaptureSettingsView().tabItem { Label("Capture", systemImage: "square.and.pencil") }
                DataSettingsView().tabItem { Label("Data", systemImage: "externaldrive") }
            }
            .environment(app).environment(tasks).environment(planning).environment(calendars).environment(nav).environment(tagColors).environment(capture)
        }
        // Menu bar icon (quick-capture Q4): keeps capture and the window one click away; hidden via Settings.
        MenuBarExtra("gly", image: "MenuBarIcon", isInserted: $showMenuBarIcon) {
            MenuBarContent(capture: capture)
        }
    }

    private func startUp() async {
        clock.onDayChange = { newDay in
            // Midnight: persist snooze transitions and advance "today" if it was shown (design L8).
            Task { await app.send(.reconcileSnoozes(today: newDay.description), asSystem: true) }
            if nav.day == newDay.adding(days: -1) { nav.day = newDay }
        }
        await app.start()
        tasks.attach(app.store, writer: app.writer)
        wiki.attach(app.store)
        planning.attach(app.store)
        tagColors.attach(app.store)
        meetingMarks.attach(app.store)
        capture.start(app: app, nav: nav, environment: { $0 })
        if app.canWrite { await app.send(.reconcileSnoozes(today: clock.today.description), asSystem: true) }
        await calendars.start()
        syncDay()
    }

    private func syncDay() {
        tasks.set(day: nav.day, today: clock.today)
        planning.set(day: nav.day, today: clock.today)
        calendars.show(day: nav.day)
    }

    /// A focused text field undoes its own typing; when it has nothing to undo (e.g. the title still has focus after a change
    /// in a property popover), ⌘Z undoes the last store change instead.
    private func undoRedo(store command: Command, text selector: Selector) {
        if let text = NSApp.keyWindow?.firstResponder as? NSText, let manager = text.undoManager,
           command == .undo ? manager.canUndo : manager.canRedo {
            NSApp.sendAction(selector, to: nil, from: nil)
        } else {
            Task { await app.undoRedo(command) }
        }
    }
}

/// Banner shown when writes aren't possible (design L2, "Risks": login item not approved).
struct AgentBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.agentState {
        case .ready, .unknown:
            EmptyView()
        case .requiresApproval:
            banner("Writing disabled: allow the gly agent in System Settings → Login Items.")
        case .unavailable(let reason):
            banner("Writing disabled: gly agent not reachable. \(reason)")
        }
    }

    private func banner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).lineLimit(2)
            Spacer()
            Button("Open Login Items") { app.openLoginItems() }
            Button("Retry") { Task { await app.refreshAgentState() } }
        }
        .padding(8)
        .background(.yellow.opacity(0.15))
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(TasksModel.self) private var tasks
    @Environment(Navigation.self) private var nav
    @Environment(BrowserModel.self) private var browser
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        @Bindable var nav = nav
        @Bindable var app = app
        VStack(spacing: 0) {
            AgentBanner()
            NavigationSplitView {
                List(selection: Binding(get: { nav.current }, set: { if let d = $0 { nav.go(d) } })) {
                    Label("Day", systemImage: "calendar").tag(Navigation.Destination.day)
                    // The browser's preset views (specs/item-browser "Item browser and preset views").
                    ForEach(ItemView.presets) { view in
                        if view.query.isEmpty {
                            Label(view.name, systemImage: view.symbol).tag(Navigation.Destination.items(view.id))
                        } else {
                            SidebarCountRow(title: view.name, symbol: view.symbol, count: SidebarCountRow.matching(view.query))
                                .tag(Navigation.Destination.items(view.id))
                        }
                    }
                    SidebarCountRow(title: "Trash", symbol: "trash", count: SidebarCountRow.recentlyDeleted).tag(Navigation.Destination.trash)
                    if !browser.saved.isEmpty {
                        Section("Saved Views") {
                            ForEach(browser.saved) { view in
                                SidebarCountRow(title: view.name, symbol: view.symbol, count: SidebarCountRow.matching(view.query))
                                    .id(view.query.description)
                                    .tag(Navigation.Destination.items(view.id))
                                    .contextMenu {
                                        Button("Rename…") { renameText = view.name; renaming = view.id }
                                        Button("Delete View", role: .destructive) {
                                            if nav.current == .items(view.id) { nav.go(.items(ItemView.all.id)) }
                                            browser.delete(view.id)
                                        }
                                    }
                            }
                        }
                    }
                    Section("Tags") { TagTreeView() }
                }
                // The main pane's minimum (600) follows from the window minimum (960) minus the widest sidebar (360).
                // Setting it on the detail column instead made the split view slide the sidebar out of the window.
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
            } detail: {
                switch nav.current {
                case .day: DayContainer()
                case .trash: TrashView()
                // One view per item: a title being edited can't carry over into the next page or task.
                case .page(let id): PageView(id: id).id(id)
                case .task(let id): TaskPageView(id: id).id(id)
                case .bookmark(let id): BookmarkPageView(id: id).id(id)
                // One browser per view: each keeps its own results and collapsed groups.
                case .items(let viewID): ItemBrowserView(viewID: viewID).id(viewID)
                case .tag(let name): TagPageView(name: name).id(name)
                case .meeting(let ref): MeetingPageView(ref: ref)
                }
            }
        }
        .alert("Rename View", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let id = renaming { browser.rename(id, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .sheet(isPresented: $nav.showQuickOpen) { QuickOpenView() }
        .sheet(isPresented: $nav.showNewPage) { NewPageSheet() }
        .overlay {
            if let notice = app.undoNotice { UndoNoticeView(notice: notice).transition(.opacity).allowsHitTesting(false) }
        }
        .animation(.easeOut(duration: 0.2), value: app.undoNotice)
        .alert("gly", isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } })) {
            Button("OK") { app.lastError = nil }
        } message: { Text(app.lastError ?? "") }
    }
}

/// Gives the capture controller a way to open the main window when none is open (⌘↩ in the panel).
struct OpenWindowHook: View {
    @Environment(\.openWindow) private var openWindow
    let capture: CaptureController
    var body: some View {
        Color.clear.onAppear { capture.openMainWindow = { openWindow(id: "main") } }
    }
}

/// The menu bar icon's menu (quick-capture Q4).
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    let capture: CaptureController
    var body: some View {
        Button("Quick Capture (\(capture.shortcut.display))") { capture.show() }
        Button("Open gly") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain && $0.isVisible }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
        }
        Divider()
        Button("Quit gly") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// Brief centered overlay after undo/redo: a rewind (or forward) arrow and what was reverted.
struct UndoNoticeView: View {
    let notice: UndoNotice

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: notice.redo ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 44, weight: .medium))
            Text(notice.label).font(.callout).multilineTextAlignment(.center).lineLimit(3)
        }
        .foregroundStyle(notice.changed ? .primary : .secondary)
        .padding(20)
        .frame(minWidth: 160, maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}

/// Wires ⌘N to the day view's "new task for the displayed day".
struct DayContainer: View {
    @Environment(Navigation.self) private var nav
    @State private var editing: TaskEditorTarget?
    var body: some View {
        @Bindable var nav = nav
        DayView(day: $nav.day)
            .onChange(of: nav.newTaskRequest) { editing = .new(due: Due(day: nav.day.description)) }
            .sheet(item: $editing) { TaskEditor(target: $0) }
    }
}

/// Which tag group a drag is over, so the whole group (tag row + its items) can be highlighted.
@MainActor
@Observable
final class TreeDropState {
    enum Target: Equatable { case tag(String), untagged }
    var target: Target?
}

extension View {
    /// Spring-loading: expands a collapsed group when a drag rests on it for a moment.
    func springLoaded(_ group: TreeDropState.Target, state: TreeDropState, expanded: Binding<Bool>) -> some View {
        onChange(of: state.target == group) { _, over in
            guard over, !expanded.wrappedValue else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if state.target == group { withAnimation { expanded.wrappedValue = true } }
            }
        }
    }
}

extension View {
    /// Makes the whole row (text included) a click, drag and drop target for a tag group (design P9).
    /// The row's content ignores the pointer (`allowsHitTesting(false)`), so its text can't swallow drops;
    /// the row itself, with a rectangular content shape, takes clicks, drags and drops.
    func treeRow(group: TreeDropState.Target, state: TreeDropState, drag: String? = nil,
                 onTap: @escaping () -> Void, onDrop: @escaping ([String]) -> Void) -> some View {
        let highlighted = state.target == group
        return self
            .allowsHitTesting(false)
            .padding(.vertical, 2).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .leading) {
                if highlighted, case .tag = group {
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 3).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .modifier(OptionalDrag(payload: drag))
            .dropDestination(for: String.self) { items, _ in
                state.target = nil
                onDrop(items)
                return true
            } isTargeted: { over in
                if over { state.target = group } else if state.target == group { state.target = nil }
            }
    }
}

private struct OptionalDrag: ViewModifier {
    let payload: String?
    func body(content: Content) -> some View {
        if let payload { content.draggable(payload) } else { content }
    }
}

/// The tag hierarchy, which doubles as the tree of everything tagged (specs/tags "Tag list", "Move items in the tree"):
/// tag rows open their tag page; open tasks and pages are leaves under their exact tags; untagged items at the end.
/// Dropping onto a tag or onto any item of its group moves the dragged item there (⌥ adds the tag instead);
/// the group being dropped into is highlighted.
/// The tag tree (specs/tags "Tag tree", item-browser I7): tags only, a filter field, counts of the current view's
/// items, and clicks that filter the current view (⇧ adds); outside the browser a click opens the tag's view.
struct TagTreeView: View {
    @Environment(TasksModel.self) private var tasks
    @Environment(WikiModel.self) private var wiki
    @Environment(AppModel.self) private var app
    @Environment(BrowserModel.self) private var browser
    @Environment(Navigation.self) private var nav
    @State private var drop = TreeDropState()
    @State private var filter = ""
    @State private var live = Live<TagCounts>()

    var body: some View {
        TextField("Filter tags", text: $filter).textFieldStyle(.roundedBorder).controlSize(.small)
        let nodes = TagTreeFilter.apply(filter, to: tasks.tagTree)
        if tasks.tagTree.isEmpty {
            Text("No tags yet").font(.caption).foregroundStyle(.secondary)
        } else if nodes.isEmpty {
            Text("No tag matches").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(nodes) { node in TagTreeNode(node: node, drop: drop, counts: live.value?.tags ?? [:], forceExpanded: !filter.isEmpty) }
        if filter.isEmpty {
            HStack {
                Label("Untagged", systemImage: "tray").foregroundStyle(.secondary)
                Spacer()
                if let n = live.value?.untagged, n > 0 { Text("\(n)").foregroundStyle(.secondary).monospacedDigit() }
            }
            .fontWeight(TagTreeClick.untaggedActive(browser) ? .bold : .regular)
            .treeRow(group: .untagged, state: drop, onTap: { TagTreeClick.untagged(browser: browser, nav: nav) }) { items in
                ItemMove.perform(items, to: nil, app: app, wiki: wiki, tasks: tasks)
            }
        }
        // Counts follow the shown view without its tag filters (item-browser I2); outside the browser, all items.
        Color.clear.frame(height: 0)
            .task(id: TagTreeClick.countQuery(browser)) {
                let q = TagTreeClick.countQuery(browser)
                live.observe(wiki.store) { db in
                    let items = try BrowseQueries.items(db, q, sort: .changed)
                    return TagCounts(tags: BrowseFacets.tagCounts(items), untagged: BrowseFacets.untaggedCount(items))
                }
            }
    }
}

struct TagCounts: Equatable {
    var tags: [String: Int]
    var untagged: Int
}

/// The tag tree filtered by typed text: tags whose path contains it, with their parents (specs/tags "Find a tag").
enum TagTreeFilter {
    static func apply(_ text: String, to nodes: [TagNode]) -> [TagNode] {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nodes }
        return nodes.compactMap { node in
            if node.path.lowercased().contains(t) { return node }
            let children = apply(t, to: node.children)
            guard !children.isEmpty else { return nil }
            var kept = node
            kept.children = children
            return kept
        }
    }
}

/// What a click in the tag tree does (specs/tags "Tag tree").
@MainActor
enum TagTreeClick {
    /// The browser view a click filters: a preset or saved view shown in the main area (tag views open other tags).
    static func target(_ browser: BrowserModel) -> String? {
        guard let id = browser.activeViewID, !browser.view(id).isTagView else { return nil }
        return id
    }

    static func countQuery(_ browser: BrowserModel) -> ItemQuery {
        browser.activeViewID.map { browser.view($0).query.droppingTags() } ?? ItemQuery()
    }

    static func tag(_ path: String, browser: BrowserModel, nav: Navigation) {
        let adding = NSEvent.modifierFlags.contains(.shift)
        if let id = target(browser) {
            var q = browser.view(id).query
            if !adding { q.tags = []; q.untagged = false }
            q.add(.tag(path))
            browser.setQuery(id, q)
        } else if adding, let id = browser.activeViewID {
            browser.setQuery(id, browser.view(id).query.adding(.tag(path)))     // a tag view narrowed by another tag
        } else {
            nav.go(.tag(path))
        }
    }

    static func untagged(browser: BrowserModel, nav: Navigation) {
        if let id = target(browser) {
            var q = browser.view(id).query
            q.tags = []; q.excludedTags = []; q.untagged = true
            browser.setQuery(id, q)
        } else {
            browser.setQuery(ItemView.all.id, ItemQuery().adding(.untagged))
            nav.go(.items(ItemView.all.id))
        }
    }

    static func isActive(_ path: String, browser: BrowserModel) -> Bool {
        guard let id = browser.activeViewID else { return false }
        return browser.view(id).query.tags.contains { TagName.key(for: $0) == TagName.key(for: path) }
    }

    static func untaggedActive(_ browser: BrowserModel) -> Bool {
        browser.activeViewID.map { browser.view($0).query.untagged } ?? false
    }
}

/// "New Subtag…" (tag tree and tag page): asks for a name, creates `parent/name` and opens its tag page.
struct NewSubtagPrompt: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(Navigation.self) private var nav
    let parent: String
    @Binding var isPresented: Bool
    var onCreate: () -> Void = {}
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New subtag of \(parent)", isPresented: $isPresented) {
            TextField("Name", text: $name)
            Button("Create", action: create).keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { name = "" }
        } message: { Text("Use / for deeper levels, e.g. work/2027.") }
    }

    private func create() {
        let child = name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        name = ""
        guard !child.isEmpty else { return }
        let path = parent + "/" + child
        Task {
            guard case .ok = await app.send(.createTag(name: path)) else { return }
            onCreate()
            nav.go(.tag(path))
        }
    }
}

/// One tag node with its child tags (no items: the browser shows them, specs/tags "Tag tree").
struct TagTreeNode: View {
    @Environment(Navigation.self) private var nav
    @Environment(WikiModel.self) private var wiki
    @Environment(TasksModel.self) private var tasks
    @Environment(AppModel.self) private var app
    @Environment(TagColorModel.self) private var tagColors
    @Environment(BrowserModel.self) private var browser
    let node: TagNode
    let drop: TreeDropState
    let counts: [String: Int]
    var forceExpanded = false
    @State private var expanded = false
    @State private var newSubtag = false
    @State private var renaming = false
    @State private var deleting = false

    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: Binding(get: { expanded || forceExpanded }, set: { expanded = $0 })) {
                ForEach(node.children) { TagTreeNode(node: $0, drop: drop, counts: counts, forceExpanded: forceExpanded) }
            } label: { row }
            .springLoaded(.tag(node.path), state: drop, expanded: $expanded)
        }
    }

    private var row: some View {
        let count = counts[TagName.key(for: node.path)] ?? 0
        let active = TagTreeClick.isActive(node.path, browser: browser) || nav.current == .tag(node.path)
        return HStack(spacing: 6) {
            Circle().fill(tagColors.color(node.path)).frame(width: 7, height: 7)
            Text(node.segment).fontWeight(active ? .bold : .regular)
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
        }
        .help("Click: show only items tagged \(node.path) · ⇧-click: add to the filter")
        .treeRow(group: .tag(node.path), state: drop, onTap: { TagTreeClick.tag(node.path, browser: browser, nav: nav) }) { items in
            ItemMove.perform(items, to: node.path, app: app, wiki: wiki, tasks: tasks)
        }
        .contextMenu {
            Button("Open Tag Page") { nav.go(.tag(node.path)) }
            Divider()
            Button("New Subtag…") { newSubtag = true }.disabled(!app.canWrite)
            Menu("Color") { TagColorMenuItems(name: node.path) }.disabled(!app.canWrite)
            Divider()
            Button("Rename…") { renaming = true }.disabled(!app.canWrite)
            Button("Delete…") { deleting = true }.disabled(!app.canWrite || !node.isTag)
        }
        .modifier(TagManagementPrompts(name: node.path, renaming: $renaming, deleting: $deleting))
        .modifier(NewSubtagPrompt(parent: node.path, isPresented: $newSubtag, onCreate: { expanded = true }))
    }
}

/// Drag & drop in the tag tree: plain = move (replace the source tag), ⌥ = alias (add), onto Untagged = remove.
/// Rows dragged from the task or page list have no source tag, so dropping them onto a tag adds it.
@MainActor
enum ItemMove {
    static func perform(_ items: [String], to target: String?, app: AppModel, wiki: WikiModel, tasks: TasksModel) {
        let alias = NSEvent.modifierFlags.contains(.option)
        for item in items {
            let parts = item.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let kind = LinkRef.Kind(rawValue: parts[0]) else { continue }
            let id = parts[1]
            let source = parts[2].isEmpty ? nil : parts[2]
            let current: [String]
            switch kind {
            case .page: guard let page = wiki.page(id) else { continue }; current = page.tags
            case .task: guard let task = tasks.task(id: id) else { continue }; current = task.tags
            case .meeting, .bookmark:
                guard let tags = try? wiki.store?.read({ try TaskQueries.tagsByItem($0, ids: [id])[id] ?? [] }) else { continue }
                current = tags
            case .tag: continue
            }
            var tags = current
            func has(_ t: String) -> Bool { tags.contains { TagName.key(for: $0) == TagName.key(for: t) } }
            if let target {
                if !alias, let source { tags.removeAll { TagName.key(for: $0) == TagName.key(for: source) } }
                if !has(target) { tags.append(target) }
            } else if let source {
                tags.removeAll { TagName.key(for: $0) == TagName.key(for: source) }
            }
            guard tags != current else { continue }
            Task {
                switch kind {
                case .page: await app.send(.updatePage(id: id, PagePatch(tags: tags)))
                case .task: await app.send(.updateTask(id: id, TaskPatch(tags: tags)))
                case .meeting: await app.send(.updateMeetingNotes(id: id, body: nil, tags: tags))
                case .bookmark: await app.send(.updateBookmark(id: id, BookmarkPatch(tags: tags)))
                case .tag: break
                }
            }
        }
    }
}
