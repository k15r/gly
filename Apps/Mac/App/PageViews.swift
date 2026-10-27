import GRDB
import SwiftUI
import WorkDashCore
import WorkDashEditor

// MARK: - Shared pieces

/// The markdown editor wired to WorkDash: link appearance, `[[` suggestions and link opening (design P8).
struct WDMarkdownEditor: View {
    @Environment(WikiModel.self) private var wiki
    @Environment(\.linkOpener) private var opener
    let text: String
    var onChange: ((String) -> Void)?
    var onCommit: ((String, String) -> Void)?

    var body: some View {
        MarkdownEditor(text: text, onChange: onChange, onCommit: onCommit,
                       appearance: { wiki.appearance($0) },
                       onOpenLink: { opener?.open($0) },
                       suggestions: { wiki.suggestions($0) },
                       linkMenu: { wiki.linkMenu($0) })
    }
}

/// Rendered markdown with WorkDash link appearance.
struct WDMarkdownReadView: View {
    @Environment(WikiModel.self) private var wiki
    let text: String
    /// Saves a checkbox toggle (one undo step each).
    var onChange: ((String) -> Void)?
    var body: some View {
        MarkdownReadView(text: text, appearance: { wiki.appearance($0) }, onChange: onChange, linkMenu: { wiki.linkMenu($0) })
    }
}

private struct LinkOpenerKey: EnvironmentKey { static let defaultValue: LinkOpener? = nil }
extension EnvironmentValues {
    var linkOpener: LinkOpener? {
        get { self[LinkOpenerKey.self] }
        set { self[LinkOpenerKey.self] = newValue }
    }
}

extension LinkRef.Kind {
    var symbol: String { linkSymbol }
}

/// "What links here" (specs/links "Backlinks").
struct BacklinksView: View {
    @Environment(Navigation.self) private var nav
    @Environment(WikiModel.self) private var wiki
    let backlinks: [Backlink]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Backlinks").font(.headline)
            if backlinks.isEmpty {
                Text("Nothing links here yet").font(.callout).foregroundStyle(.secondary)
            } else {
                let names = wiki.displayNames(backlinks.map(\.source.id))
                ForEach(backlinks) { b in
                    Button { open(b.source) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(names[b.source.id]?.display ?? b.source.title, systemImage: b.source.kind.symbol).fontWeight(.medium)
                            if !b.excerpt.isEmpty { Text(b.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func open(_ ref: LinkRef) {
        switch ref.kind {
        case .page: nav.go(.page(ref.id))
        case .task: nav.go(.task(ref.id))
        case .tag: nav.go(.tag(ref.title))
        }
    }
}

// MARK: - Pages list

struct PagesListView: View {
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pages").font(.title2.bold())
                if let tag = wiki.pageTagFilter {
                    HStack(spacing: 4) {
                        TagChip(name: tag.display)
                        Button { wiki.pageTagFilter = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Button { nav.showNewPage = true } label: { Label("New Page", systemImage: "plus") }.disabled(!app.canWrite)
            }
            .padding()
            Divider()
            if wiki.pages.isEmpty {
                Text(wiki.pageTagFilter == nil ? "No pages yet" : "No pages with this tag").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let names = wiki.displayNames(wiki.pages.map(\.id))
                List(wiki.pages) { page in
                    // A plain row with a tap, not a Button: a Button swallows the mouse-down and the row couldn't be dragged.
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            // The title stands alone: a qualifier tag is emphasized among the chips instead,
                            // and a date qualifier ("created …", identical tags) is the created date on the right.
                            let qualifier = names[page.id]?.qualifier
                            let qualifierIsTag = qualifier.map { page.tags.contains($0) } ?? false
                            Text(page.title).font(.headline).lineLimit(1)
                            let excerpt = TreeLeaf.excerpt(of: page.body)
                            if !excerpt.isEmpty { Text(excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                            if !page.tags.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(page.tags, id: \.self) { TagChip(name: $0, emphasized: qualifierIsTag && $0 == qualifier) }
                                }.padding(.top, 1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("edited ") + Text(page.modifiedAt, format: .relative(presentation: .named))
                            Text("created ") + Text(page.createdAt, format: .dateTime.day().month(.abbreviated).year())
                        }
                        .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { nav.go(.page(page.id)) }
                    .draggableItem(.page, id: page.id, title: page.title)
                }
            }
        }
    }
}

// MARK: - Page view

struct PageDetail: Equatable {
    var page: PageItem?
    var backlinks: [Backlink]
}

/// One page: title, tags, editor or read view, backlinks (specs/info-pages, specs/links).
struct PageView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    let id: String

    @State private var live = Live<PageDetail>()
    @State private var title = ""
    @State private var tags: [String] = []
    @State private var pendingTag = ""
    @State private var editing: Bool?
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if let detail = live.value, let page = detail.page {
                content(page, backlinks: detail.backlinks)
            } else if live.loaded {
                ContentUnavailableView("Page not found", systemImage: "doc.questionmark", description: Text("It may have been deleted."))
            } else {
                ProgressView()
            }
        }
        .task(id: id) {
            editing = nil
            let id = self.id
            live.observe(wiki.store) { db in
                PageDetail(page: try PageQueries.page(db, id: id), backlinks: try LinkQueries.backlinks(db, to: id))
            }
        }
        .onChange(of: live.value?.page) { _, page in
            guard let page else { return }
            if !titleFocused { title = page.title }
            tags = page.tags
            if editing == nil { editing = page.body.isEmpty }
        }
    }

    private func content(_ page: PageItem, backlinks: [Backlink]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Title", text: $title).font(.title.bold()).textFieldStyle(.plain)
                    .focused($titleFocused)
                    .onSubmit(saveTitle)
                    .onChange(of: titleFocused) { _, focused in if !focused { saveTitle() } }
                Spacer()
                Picker("", selection: Binding(get: { editing ?? false }, set: { editing = $0 })) {
                    Text("Read").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented).fixedSize()
                .help("Switch between reading and editing (⌘E)")
                Button("") { editing = !(editing ?? false) }.keyboardShortcut("e").hidden().frame(width: 0)
                Menu {
                    Button("Delete Page", role: .destructive) { Task { await app.send(.deletePage(id: page.id)); nav.back() } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding([.horizontal, .top])
            Form { TagField(tags: $tags, input: $pendingTag) }
                .formStyle(.columns).padding(.horizontal)
                .onChange(of: tags) { _, new in
                    guard new != page.tags else { return }
                    Task { await app.send(.updatePage(id: page.id, PagePatch(tags: new))) }
                }
            Divider().padding(.top, 8)
            if editing == true {
                WDMarkdownEditor(text: page.body, onCommit: { text, session in
                    Task { await app.send(.updatePage(id: page.id, PagePatch(body: text, session: session))) }
                })
                .frame(maxHeight: .infinity)
                Divider()
                BacklinksView(backlinks: backlinks).padding().frame(maxHeight: 180, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if page.body.isEmpty {
                            Text("Empty page – switch to Edit (⌘E) to write.").foregroundStyle(.secondary)
                        } else {
                            WDMarkdownReadView(text: page.body) { new in
                                Task { await app.send(.updatePage(id: page.id, PagePatch(body: new))) }
                            }
                        }
                        Divider()
                        BacklinksView(backlinks: backlinks)
                    }
                    .padding()
                }
            }
        }
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let page = live.value?.page else { return }
        guard !trimmed.isEmpty else { title = page.title; return }
        guard trimmed != page.title else { return }
        Task { await app.send(.updatePage(id: page.id, PagePatch(title: trimmed))) }
    }
}

// MARK: - Tag page

struct TagPageDetail: Equatable {
    var data: TagPageData
    var backlinks: [Backlink]
}

/// A tag's page: description, open tasks, pages, finished tasks, backlinks (specs/tag-pages).
struct TagPageView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(TasksModel.self) private var tasks
    @Environment(Navigation.self) private var nav
    @Environment(Clock.self) private var clock
    let name: String

    @State private var live = Live<TagPageDetail>()
    @State private var editing = false
    @State private var showFinished = false
    @State private var newSubtag = false
    @State private var renaming = false
    @State private var deleting = false

    var body: some View {
        Group {
            if let detail = live.value { content(detail) } else { ProgressView() }
        }
        .task(id: name) {
            editing = false
            guard let tag = try? TagName(name) else { return }
            let today = clock.today
            live.observe(wiki.store) { db in
                let data = try TagPageQueries.page(db, name: tag, today: today)
                let backlinks = try data.tagID.map { try LinkQueries.backlinks(db, to: $0, isTag: true) } ?? []
                return TagPageDetail(data: data, backlinks: backlinks)
            }
        }
    }

    private func content(_ detail: TagPageDetail) -> some View {
        let data = detail.data
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(data.name, systemImage: "tag").font(.title.bold())
                    TagColorControl(name: data.name)
                    Spacer()
                    Button("Show in Tasks") {
                        tasks.tagFilter = try? TagName(data.name)
                        nav.go(.tasks)
                    }
                    Button("Show in Pages") {
                        wiki.pageTagFilter = try? TagName(data.name)
                        nav.go(.pages)
                    }
                    Button { newSubtag = true } label: { Label("New Subtag", systemImage: "tag") }.disabled(!app.canWrite)
                    Button { nav.showNewPage = true } label: { Label("New Page", systemImage: "plus") }.disabled(!app.canWrite)
                    Toggle("Edit", isOn: $editing).toggleStyle(.button).keyboardShortcut("e")
                    Menu {
                        Button("Rename…") { renaming = true }
                        Button("Delete…") { deleting = true }.disabled(data.tagID == nil)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(!app.canWrite)
                }
                .modifier(NewSubtagPrompt(parent: data.name, isPresented: $newSubtag))
                .modifier(TagManagementPrompts(name: data.name, renaming: $renaming, deleting: $deleting))
                if editing {
                    WDMarkdownEditor(text: data.body, onCommit: { text, session in
                        Task { await app.send(.updateTagPage(name: data.name, body: text, session: session)) }
                    })
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                } else if data.body.isEmpty {
                    Text("No description – click Edit to describe this \(data.name.contains("/") ? "tag" : "group").").foregroundStyle(.secondary)
                } else {
                    WDMarkdownReadView(text: data.body) { new in
                        Task { await app.send(.updateTagPage(name: data.name, body: new)) }
                    }
                }

                section("Open tasks", count: data.openTasks.count) {
                    ForEach(data.openTasks) { task in
                        TaskRow(task: task, onEdit: { nav.go(.task(task.id)) })
                    }
                }
                section("Pages", count: data.pages.count) {
                    let names = wiki.displayNames(data.pages.map(\.id))
                    ForEach(data.pages) { page in
                        Button { nav.go(.page(page.id)) } label: {
                            HStack { Label(names[page.id]?.display ?? page.title, systemImage: "doc.text"); Spacer()
                                Text(page.modifiedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                DisclosureGroup("Finished tasks (\(data.finishedTasks.count))", isExpanded: $showFinished) {
                    ForEach(data.finishedTasks) { task in
                        TaskRow(task: task, onEdit: { nav.go(.task(task.id)) })
                    }
                }
                Divider()
                BacklinksView(backlinks: detail.backlinks)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func section(_ title: String, count: Int, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(count))").font(.headline)
            if count == 0 { Text("None").font(.callout).foregroundStyle(.secondary) } else { content() }
        }
    }
}

// MARK: - Quick open (⌘K)

struct QuickOpenView: View {
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    @Environment(\.linkOpener) private var opener
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private enum Row: Identifiable {
        case hit(SearchHit)
        case create(String)
        var id: String { switch self { case .hit(let h): h.ref.kind.rawValue + h.id; case .create(let t): "create:" + t } }
    }

    private var rows: [Row] {
        let results = wiki.search(query)
        var rows = results.all.map(Row.hit)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, !results.pages.contains(where: { $0.ref.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            rows.append(.create(trimmed))
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search pages, tasks and tags", text: $query)
                .textFieldStyle(.plain).font(.title3).padding(12)
                .focused($focused)
                .onSubmit { choose(rows) }
                .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, rows.count - 1)); return .handled }
                .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
                .onChange(of: query) { selected = 0 }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index == selected ? Color.accentColor.opacity(0.2) : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = index; choose(rows) }
                    }
                }
            }
            .frame(height: 320)
        }
        .frame(width: 560)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .hit(let hit):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: hit.ref.kind.symbol).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wiki.displayNames([hit.ref.id])[hit.ref.id]?.display ?? hit.ref.title).lineLimit(1)
                    Text(WikiModel.secondLine(kind: hit.ref.kind, tags: hit.tags, modified: hit.modifiedAt))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    if !hit.excerpt.isEmpty { Text(hit.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        case .create(let title):
            Label("Create page “\(title)”", systemImage: "plus.circle")
        }
    }

    private func choose(_ rows: [Row]) {
        guard rows.indices.contains(selected) else { return }
        dismiss()
        switch rows[selected] {
        case .hit(let hit):
            switch hit.ref.kind {
            case .page: nav.go(.page(hit.ref.id))
            case .task: nav.go(.task(hit.ref.id))
            case .tag: nav.go(.tag(hit.ref.title))
            }
        case .create(let title):
            Task { await opener?.createPage(title: title) }
        }
    }
}

// MARK: - New page

struct NewPageSheet: View {
    @Environment(Navigation.self) private var nav
    @Environment(\.linkOpener) private var opener
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Page").font(.title3.bold())
            TextField("Title", text: $title, prompt: Text("Required")).onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding().frame(width: 400)
    }

    private func create() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        // A new page from a tag page gets that tag.
        var tags: [String] = []
        if case .tag(let name) = nav.current { tags = [name] }
        dismiss()
        Task { await opener?.createPage(title: t, tags: tags) }
    }
}
