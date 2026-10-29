import AppKit
import SwiftUI
import GlyCore

/// The item browser (specs/item-browser): a view's filter bar, group and sort menus, and its results.
/// Presets, saved views and tag views (with `header`) all use it.
struct ItemBrowserView<Header: View>: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(WikiModel.self) private var wiki
    @Environment(AppModel.self) private var app
    @Environment(Navigation.self) private var nav
    @Environment(Clock.self) private var clock
    @Environment(PlanningModel.self) private var planning
    let viewID: String
    @ViewBuilder var header: () -> Header

    @State private var live = Live<[BrowseItem]>()
    @State private var collapsed: Set<String> = []
    @State private var newTask: TaskEditorTarget?
    @State private var newBookmark = false
    @State private var savingView = false
    @State private var viewName = ""

    /// What the results depend on; a change re-runs the observation.
    private struct Key: Hashable { let query: ItemQuery; let sort: ItemSort; let today: LocalDay; let workdays: Set<Int> }

    var body: some View {
        let view = browser.view(viewID)
        let items = live.value ?? []
        VStack(alignment: .leading, spacing: 0) {
            header()
            toolbar(view, count: items.count)
            FilterBar(query: Binding(get: { browser.view(viewID).query }, set: { browser.setQuery(viewID, $0) }))
                .padding(.horizontal).padding(.bottom, 6)
            Divider()
            results(view, items: items)
        }
        .task(id: Key(query: view.query, sort: view.sort, today: clock.today, workdays: planning.hours.workdays)) {
            let q = view.query, sort = view.sort, workdays = planning.hours.workdays
            live.observe(wiki.store) { db in try BrowseQueries.items(db, q, sort: sort, workdays: workdays) }
        }
        .onAppear { browser.activeViewID = viewID; collapsed = [] }
        .onDisappear { if browser.activeViewID == viewID { browser.activeViewID = nil } }
        .sheet(item: $newTask) { TaskEditor(target: $0) }
        .onChange(of: nav.saveViewRequest) { startSaving() }
        // ⌘N (Navigation.requestNew): a task with the view's tags, as "New Task".
        .onChange(of: nav.newTaskRequest) { newTask = .new(due: nil, tags: browser.view(viewID).query.tags) }
        .alert("Save View", isPresented: $savingView) {
            TextField("Name", text: $viewName)
            Button("Save") {
                let name = viewName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { if let id = await browser.saveView(from: viewID, name: name) { nav.go(.items(id)) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The filter, grouping and sorting appear as a view in the sidebar.") }
    }

    // MARK: Toolbar

    private func toolbar(_ view: ItemView, count: Int) -> some View {
        HStack(spacing: 10) {
            if !view.isTagView {
                Label(view.name, systemImage: view.symbol).font(.title2.bold()).labelStyle(.titleAndIcon)
            }
            Text("\(count) item\(count == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            // Task groupings and orders only where tasks can be among the results; Kind only with several kinds.
            let tasks = view.query.kinds.isEmpty || view.query.kinds.contains(.task)
            Menu {
                Picker("Group", selection: binding(\.grouping)) {
                    ForEach(ItemGrouping.allCases.filter { g in
                        (tasks || !g.tasksOnly) && (g != .kind || view.query.kinds.count != 1) || g == view.grouping
                    }, id: \.self) { g in Text(Self.groupingLabel(g)).tag(g) }
                }
                .pickerStyle(.inline)
            } label: { Label("Group", systemImage: "rectangle.3.group") }
            .fixedSize()
            Menu {
                Picker("Sort", selection: binding(\.sort)) {
                    ForEach(ItemSort.allCases.filter { s in tasks || ![.due, .taskOrder].contains(s) || s == view.sort }, id: \.self) { s in
                        Text(Self.sortLabel(s)).tag(s)
                    }
                }
                .pickerStyle(.inline)
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            .fixedSize()
            if browser.isModified(viewID) {
                if browser.isSaved(viewID) {
                    Button("Update View") { browser.updateSaved(viewID) }.help("Save these changes into “\(view.name)”")
                }
                Button("Reset") { browser.reset(viewID) }.help("Back to the view's own filter")
            }
            // Prominent once the filter was changed: that is when there is something to save (⌘S).
            if browser.isModified(viewID) {
                Button { startSaving() } label: { Label("Save View…", systemImage: "star") }
                    .buttonStyle(.borderedProminent).help("Save this filter, grouping and sorting as a view in the sidebar (⌘S)")
            } else {
                Button { startSaving() } label: { Label("Save View…", systemImage: "star") }
                    .help("Save this filter, grouping and sorting as a view in the sidebar (⌘S)")
            }
            newMenu(view)
        }
        .padding()
    }

    /// Suggests a name from the filter ("Tasks #project/atlas due:week"), editable before saving.
    private func startSaving() {
        let view = browser.view(viewID)
        let base = view.isTagView ? "" : view.name + " "
        viewName = (base + view.query.description).trimmingCharacters(in: .whitespaces)
        savingView = true
    }

    static func groupingLabel(_ g: ItemGrouping) -> String {
        switch g {
        case .none: "No grouping"
        case .kind: "Kind"
        case .due: "Due date"
        case .status: "Status"
        case .priority: "Priority"
        case .effort: "Effort"
        case .changed: "Last change"
        case .tag: "Tag"
        }
    }

    static func sortLabel(_ s: ItemSort) -> String {
        switch s {
        case .relevance: "Relevance"
        case .changed: "Last change"
        case .due: "Due date"
        case .title: "Title"
        case .taskOrder: "Task order"
        }
    }

    private func binding<T>(_ path: WritableKeyPath<ItemView, T>) -> Binding<T> {
        Binding(get: { browser.view(viewID)[keyPath: path] }, set: { value in browser.update(viewID) { $0[keyPath: path] = value } })
    }

    /// New Task / Page / Bookmark for the view's kind, a menu otherwise; the view's tags come along (spec "Create from a view").
    @ViewBuilder
    private func newMenu(_ view: ItemView) -> some View {
        let tags = view.query.tags
        let kinds = view.query.kinds
        Group {
            if kinds == [.task] {
                Button { newTask = .new(due: nil, tags: tags) } label: { Label("New Task", systemImage: "plus") }
            } else if kinds == [.page] {
                Button { nav.newPageTags = tags; nav.showNewPage = true } label: { Label("New Page", systemImage: "plus") }
            } else if kinds == [.bookmark] {
                Button { newBookmark = true } label: { Label("New Bookmark", systemImage: "plus") }
            } else {
                Menu {
                    Button("New Task") { newTask = .new(due: nil, tags: tags) }
                    Button("New Page") { nav.newPageTags = tags; nav.showNewPage = true }
                    Button("New Bookmark") { newBookmark = true }
                } label: { Label("New", systemImage: "plus") }
                .fixedSize()
            }
        }
        .disabled(!app.canWrite)
        .popover(isPresented: $newBookmark, arrowEdge: .bottom) { BookmarkEditor(tags: tags, wiki: wiki) { newBookmark = false } }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ view: ItemView, items: [BrowseItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(live.loaded ? (view.query.isEmpty ? "Nothing here yet" : "No items match") : "",
                                   systemImage: live.loaded ? "tray" : "hourglass",
                                   description: Text(view.query.isEmpty || !live.loaded ? "" : "Remove a filter to see more."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = BrowseGroups.group(items, by: view.grouping, query: view.query, sort: view.sort, today: clock.today)
            // A plain move replaces the view's tag only when it has exactly one (specs/tags "Move items in the tree").
            let source = view.query.tags.count == 1 ? view.query.tags[0] : nil
            List {
                ForEach(groups) { group in
                    if view.grouping == .none {
                        ForEach(group.items) { ItemRow(item: $0, sourceTag: source) }
                    } else {
                        // Own header with a chevron: List sections only collapse natively in sidebar-style lists.
                        let open = collapsed.contains(group.id) == group.collapsed
                        Section {
                            if open { ForEach(group.items) { ItemRow(item: $0, sourceTag: source) } }
                        } header: {
                            Button { withAnimation(.easeOut(duration: 0.15)) { toggle(group, open: !open) } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right").font(.caption.bold())
                                        .rotationEffect(.degrees(open ? 90 : 0))
                                    Text(group.title)
                                    Text("\(group.items.count)").foregroundStyle(.secondary).monospacedDigit()
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(open ? "Collapse" : "Expand")
                        }
                    }
                }
            }
        }
    }

    /// `collapsed` holds the groups whose state differs from their default.
    private func toggle(_ group: ItemGroup, open: Bool) {
        let differs = open == group.collapsed
        if differs { collapsed.insert(group.id) } else { collapsed.remove(group.id) }
    }
}

extension ItemBrowserView where Header == EmptyView {
    init(viewID: String) { self.init(viewID: viewID, header: { EmptyView() }) }
}

// MARK: - Rows (specs/item-browser "Item rows")

/// How items open: a click shows the item's page, ⌘-click its link (a bookmark's URL) or else its page.
@MainActor
enum ItemOpen {
    static func page(_ item: BrowseItem, nav: Navigation) {
        switch item.kind {
        case .task: nav.go(.task(item.id))
        case .page: nav.go(.page(item.id))
        case .bookmark: nav.go(.bookmark(item.id))
        case .meeting: nav.go(.meeting(.notes(item.id)))
        }
    }

    static func click(_ item: BrowseItem, nav: Navigation) {
        if NSEvent.modifierFlags.contains(.command), let url = item.url { BookmarkOpen.url(url) } else { page(item, nav: nav) }
    }
}

/// One result: the task row for tasks (status bar, chips, quick actions), the same layout for the other kinds.
struct ItemRow: View {
    @Environment(Navigation.self) private var nav
    @Environment(AppModel.self) private var app
    let item: BrowseItem
    /// The view's only tag filter: a plain drop on another tag moves the item away from it.
    let sourceTag: String?

    var body: some View {
        Group {
            if let task = item.task {
                TaskRow(task: task, onEdit: { nav.go(.task(task.id)) })
            } else {
                generic
                    .contentShape(Rectangle())
                    .onTapGesture { ItemOpen.click(item, nav: nav) }
                    .contextMenu { menu }
            }
        }
        .draggable(item.kind.linkKind.rawValue + "\n" + item.id + "\n" + (sourceTag ?? "")) {
            Label(item.title, systemImage: item.kind.linkKind.symbol).padding(6)
        }
    }

    private var generic: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The status bar's place, so titles line up with task rows.
            RoundedRectangle(cornerRadius: 1.5).fill(Color.clear).frame(width: 3, height: 16)
            Image(systemName: item.kind.linkKind.symbol).foregroundStyle(.secondary).frame(width: 18)
            // Same layout as task rows: title, then metadata left and tags right, then the start of the text.
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).lineLimit(1)
                HStack(spacing: 4) {
                    Group {
                        if item.kind == .bookmark, let url = item.url {
                            Text(URLComponents(string: url)?.host ?? url)
                        } else {
                            Text("edited ") + Text(item.modifiedAt, format: .relative(presentation: .named))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    TagChipLine(tags: item.tags)
                }
                let excerpt = item.excerpt
                if !excerpt.isEmpty { Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(.vertical, 2)
        .help(item.url ?? "")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open") { ItemOpen.page(item, nav: nav) }
        if let url = item.url {
            Button("Open URL") { BookmarkOpen.url(url) }
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) }
        }
        Divider()
        Button("Delete", role: .destructive) {
            let id = item.id
            Task {
                switch item.kind {
                case .page: await app.send(.deletePage(id: id))
                case .bookmark: await app.send(.deleteBookmark(id: id))
                case .meeting: await app.send(.deleteMeetingNotes(id: id))
                case .task: await app.send(.deleteTask(id: id))
                }
            }
        }
        .disabled(!app.canWrite)
    }
}
