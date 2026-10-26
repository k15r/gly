import AppKit
import SwiftUI
import WorkDashCore

@main
struct WorkDashApp: App {
    @State private var app = AppModel()
    @State private var calendars = CalendarModel()
    @State private var tasks = TasksModel()
    @State private var clock = Clock()
    @State private var nav = Navigation()
    @State private var wiki = WikiModel()

    var body: some Scene {
        WindowGroup("WorkDash") {
            let opener = LinkOpener(app: app, wiki: wiki, nav: nav)
            ContentView()
                .environment(app).environment(calendars).environment(tasks).environment(clock).environment(nav).environment(wiki)
                .environment(\.linkOpener, opener)
                .environment(\.openURL, OpenURLAction { url in opener.open(url); return .handled })
                .frame(minWidth: 880, minHeight: 580)
                .task { await startUp() }
                .onChange(of: app.store === nil) { tasks.attach(app.store, writer: app.writer); wiki.attach(app.store) }
                .onChange(of: nav.day) { syncDay() }
                .onChange(of: clock.today) { syncDay() }
        }
        .commands {
            // Store undo/redo via the agent; while a text field is focused, the text's own undo applies (design L6).
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
                Button("Tasks") { nav.go(.tasks) }.keyboardShortcut("2")
                Button("Pages") { nav.go(.pages) }.keyboardShortcut("3")
            }
            CommandMenu("Developer") {
                Button("Re-check Agent") { Task { await app.refreshAgentState() } }
                Button("Unregister Agent") { Task { await app.unregisterAgent() } }
            }
        }

        Settings {
            AgentsSettingsView()
                .environment(app).environment(tasks)
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
        if app.canWrite { await app.send(.reconcileSnoozes(today: clock.today.description), asSystem: true) }
        await calendars.start()
        syncDay()
    }

    private func syncDay() {
        tasks.set(day: nav.day, today: clock.today)
        calendars.show(day: nav.day)
    }

    private func undoRedo(store command: Command, text selector: Selector) {
        if NSApp.keyWindow?.firstResponder is NSText {
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
            banner("Writing disabled: allow the WorkDash agent in System Settings → Login Items.")
        case .unavailable(let reason):
            banner("Writing disabled: WorkDash agent not reachable. \(reason)")
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

    var body: some View {
        @Bindable var nav = nav
        @Bindable var app = app
        VStack(spacing: 0) {
            AgentBanner()
            NavigationSplitView {
                List(selection: Binding(get: { nav.current }, set: { if let d = $0 { nav.go(d) } })) {
                    Label("Day", systemImage: "calendar").tag(Navigation.Destination.day)
                    Label("Tasks", systemImage: "checklist").tag(Navigation.Destination.tasks)
                    Label("Pages", systemImage: "doc.text").tag(Navigation.Destination.pages)
                    Label("Calendars", systemImage: "calendar.badge.checkmark").tag(Navigation.Destination.calendars)
                    Section("Tags") { TagTreeView() }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } detail: {
                switch nav.current {
                case .day: DayContainer()
                case .tasks: TaskListContainer()
                case .pages: PagesListView()
                case .calendars: CalendarListView()
                case .page(let id): PageView(id: id)
                case .task(let id): TaskPageView(id: id)
                case .tag(let name): TagPageView(name: name)
                }
            }
        }
        .sheet(isPresented: $nav.showQuickOpen) { QuickOpenView() }
        .sheet(isPresented: $nav.showNewPage) { NewPageSheet() }
        .overlay {
            if let notice = app.undoNotice { UndoNoticeView(notice: notice).transition(.opacity).allowsHitTesting(false) }
        }
        .animation(.easeOut(duration: 0.2), value: app.undoNotice)
        .alert("WorkDash", isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } })) {
            Button("OK") { app.lastError = nil }
        } message: { Text(app.lastError ?? "") }
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

struct TaskListContainer: View {
    @Environment(Navigation.self) private var nav
    @State private var editing: TaskEditorTarget?
    var body: some View {
        TaskListView()
            .onChange(of: nav.newTaskRequest) { editing = .new(due: nil) }
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
    /// Makes the whole row (text included) a click, drag and drop target for a tag group (design P9).
    /// A transparent layer on top takes the events, so the row's text can't swallow drops.
    func treeRow(group: TreeDropState.Target, state: TreeDropState, drag: String? = nil,
                 onTap: @escaping () -> Void, onDrop: @escaping ([String]) -> Void) -> some View {
        let highlighted = state.target == group
        return self
            .padding(.vertical, 2).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .leading) {
                if highlighted, case .tag = group {
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 3)
                }
            }
            .overlay {
                Color.clear
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
struct TagTreeView: View {
    @Environment(TasksModel.self) private var tasks
    @Environment(WikiModel.self) private var wiki
    @Environment(AppModel.self) private var app
    @State private var drop = TreeDropState()
    @State private var untaggedExpanded = false

    var body: some View {
        if tasks.tagTree.isEmpty && wiki.untagged.isEmpty {
            Text("No tags yet").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(tasks.tagTree) { node in TagTreeNode(node: node, drop: drop) }
        if !wiki.untagged.isEmpty {
            DisclosureGroup(isExpanded: $untaggedExpanded) {
                ForEach(wiki.untagged) { leaf in TreeLeafRow(leaf: leaf, fromTag: nil, drop: drop) }
            } label: {
                Label("Untagged (\(wiki.untagged.count))", systemImage: "tray").foregroundStyle(.secondary)
                    .treeRow(group: .untagged, state: drop, onTap: { untaggedExpanded.toggle() }) { items in
                        ItemMove.perform(items, to: nil, app: app, wiki: wiki, tasks: tasks)
                    }
            }
        }
    }
}

/// One tag node with its child tags, open tasks and pages.
struct TagTreeNode: View {
    @Environment(Navigation.self) private var nav
    @Environment(WikiModel.self) private var wiki
    @Environment(TasksModel.self) private var tasks
    @Environment(AppModel.self) private var app
    let node: TagNode
    let drop: TreeDropState
    @State private var expanded = false

    var body: some View {
        if node.children.isEmpty && node.items.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(node.children) { TagTreeNode(node: $0, drop: drop) }
                ForEach(node.items) { TreeLeafRow(leaf: $0, fromTag: node.path, drop: drop) }
            } label: { row }
        }
    }

    private var row: some View {
        HStack {
            Text(node.segment).fontWeight(nav.current == .tag(node.path) ? .bold : .regular)
            Spacer()
            if node.openCount > 0 { Text("\(node.openCount)").foregroundStyle(.secondary).monospacedDigit() }
        }
        .treeRow(group: .tag(node.path), state: drop, onTap: { nav.go(.tag(node.path)) }) { items in
            ItemMove.perform(items, to: node.path, app: app, wiki: wiki, tasks: tasks)
        }
    }
}

/// A task or page leaf in the tag tree. Dropping onto it drops into its tag group.
struct TreeLeafRow: View {
    @Environment(Navigation.self) private var nav
    @Environment(WikiModel.self) private var wiki
    @Environment(TasksModel.self) private var tasks
    @Environment(AppModel.self) private var app
    let leaf: TreeLeaf
    let fromTag: String?
    let drop: TreeDropState

    private var symbol: String {
        switch leaf.kind {
        case .page: "doc.text"
        case .task: leaf.snoozed ? "moon.zzz" : "circle"
        case .tag: "tag"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(leaf.snoozed ? Color.blue : .secondary).imageScale(.small)
            Text(leaf.title).lineLimit(1)
                .fontWeight(nav.current == .page(leaf.itemID) || nav.current == .task(leaf.itemID) ? .bold : .regular)
                .foregroundStyle(leaf.snoozed ? .secondary : .primary)
            Spacer()
            if !leaf.otherTags.isEmpty {
                Image(systemName: "link").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .help(([leaf.snoozed ? "Snoozed" : nil] + [leaf.otherTags.isEmpty ? nil : "Also in " + leaf.otherTags.joined(separator: ", ")])
            .compactMap { $0 }.joined(separator: " · "))
        .treeRow(group: fromTag.map { .tag($0) } ?? .untagged, state: drop,
                 drag: leaf.kind.rawValue + "\n" + leaf.itemID + "\n" + (fromTag ?? ""),
                 onTap: {
                     switch leaf.kind {
                     case .page: nav.go(.page(leaf.itemID))
                     case .task: nav.go(.task(leaf.itemID))
                     case .tag: break
                     }
                 }) { items in
            ItemMove.perform(items, to: fromTag, app: app, wiki: wiki, tasks: tasks)
        }
    }
}

/// Drag & drop in the tag tree: plain = move (replace the source tag), ⌥ = alias (add), onto Untagged = remove.
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
                case .tag: break
                }
            }
        }
    }
}
