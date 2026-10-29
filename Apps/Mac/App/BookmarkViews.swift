import AppKit
import SwiftUI
import GlyCore

/// The bookmark editor (bookmarks B4): title, URL, description and tags. For a URL that is already bookmarked it
/// edits that bookmark (specs/bookmarks "Same URL again"); otherwise "Save" creates one.
struct BookmarkEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    let onDone: () -> Void

    /// The bookmark being edited; nil while adding.
    @State private var editing: BookmarkItem?
    @State private var title: String
    @State private var url: String
    @State private var description: String
    @State private var tags: [String]
    @State private var pendingTag = ""
    @State private var problem: String?
    @FocusState private var titleFocused: Bool

    /// Adding from a link (prefilled with its label and URL) or with empty fields; an existing bookmark of the URL opens instead.
    init(url: String = "", label: String = "", tags: [String] = [], wiki: WikiModel, onDone: @escaping () -> Void) {
        let existing = url.isEmpty ? nil : wiki.bookmark(for: url)
        self.init(existing: existing, url: url, title: label, onDone: onDone)
        if existing == nil { _tags = State(initialValue: tags) }
    }

    init(bookmark: BookmarkItem, onDone: @escaping () -> Void) { self.init(existing: bookmark, url: bookmark.url, title: bookmark.title, onDone: onDone) }

    private init(existing: BookmarkItem?, url: String, title: String, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _editing = State(initialValue: existing)
        _title = State(initialValue: existing?.title ?? title)
        _url = State(initialValue: existing?.url ?? url)
        _description = State(initialValue: existing?.description ?? "")
        _tags = State(initialValue: existing?.tags ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(editing == nil ? "Add Bookmark" : "Edit Bookmark", systemImage: "bookmark").font(.headline)
                Spacer()
                if let editing {
                    Button(role: .destructive) { delete(editing) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Delete bookmark (it goes to the Trash)").disabled(!app.canWrite)
                }
            }
            TextField("Title", text: $title, prompt: Text("Title (the host when empty)")).focused($titleFocused)
            TextField("URL", text: $url, prompt: Text("https://…"))
            if let other = duplicate {
                // Typing a URL that is already bookmarked: offer that bookmark instead of a second one.
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill").foregroundStyle(.secondary)
                    Text("Already bookmarked as “\(other.title)”").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Button("Edit it") { load(other) }.buttonStyle(.link)
                }
            }
            TextField("Description", text: $description, prompt: Text("Description"), axis: .vertical).lineLimit(3...6)
            TagField(tags: $tags, input: $pendingTag)
            if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
            HStack {
                if let editing {
                    Button("Open Page") { onDone(); nav.go(.bookmark(editing.id)) }
                }
                Spacer()
                Button("Cancel", action: onDone).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(!app.canWrite || BookmarkURL.normalize(url) == nil || duplicate != nil)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        .frame(width: 360)
        .onAppear { titleFocused = editing == nil }
    }

    /// Another live bookmark with the typed URL.
    private var duplicate: BookmarkItem? {
        guard let other = wiki.bookmark(for: url), other.id != editing?.id else { return nil }
        return other
    }

    private func load(_ b: BookmarkItem) {
        editing = b; title = b.title; url = b.url; description = b.description; tags = b.tags; problem = nil
    }

    private func save() {
        var names = tags
        // A tag still being typed counts, as in the task editor.
        let typed = pendingTag.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, !names.contains(where: { TagName.key(for: $0) == TagName.key(for: typed) }) { names.append(typed) }
        let command: Command = if let editing {
            .updateBookmark(id: editing.id, BookmarkPatch(title: title, url: url, description: description, tags: names))
        } else {
            .createBookmark(BookmarkDraft(url: url, title: title, description: description, tags: names))
        }
        Task {
            switch await app.send(command, quiet: true) {
            case .ok(let r) where editing == nil && !r.changed:
                // Saved meanwhile under the same URL: show that one (spec "Same URL again").
                if let id = r.id, let existing = wiki.bookmarks.first(where: { $0.id == id }) { load(existing) }
                problem = r.message
            case .ok: onDone()
            case .failure(let f): problem = f.message
            }
        }
    }

    private func delete(_ b: BookmarkItem) {
        Task { if case .ok = await app.send(.deleteBookmark(id: b.id)) { onDone() } }
    }
}

/// Opens a bookmark's URL in the default browser (⌘-click everywhere, item-browser I6).
enum BookmarkOpen {
    static func url(_ string: String) { if let url = URL(string: string) { NSWorkspace.shared.open(url) } }
}

struct BookmarkDetail: Equatable {
    var bookmark: BookmarkItem?
    var linkedFrom: [Backlink]
}

/// A bookmark in the main area, laid out like a page or a task: title, URL, tags, the description in the editor and
/// where it is linked from. Every change is saved at once; each field change and each description edit session is one undo step.
struct BookmarkPageView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    let id: String

    @State private var live = Live<BookmarkDetail>()
    @State private var title = ""
    @State private var url = ""
    @State private var tags: [String] = []
    @State private var pendingTag = ""
    @State private var problem: String?
    /// Opened from quick capture (⌘Return): the cursor goes into the description.
    @State private var focusText = false
    @FocusState private var focus: Field?
    enum Field { case title, url }

    var body: some View {
        Group {
            if let detail = live.value, let b = detail.bookmark {
                content(b, linkedFrom: detail.linkedFrom)
            } else if live.loaded {
                ContentUnavailableView("Bookmark not found", systemImage: "bookmark.slash", description: Text("It may have been deleted."))
            } else {
                ProgressView()
            }
        }
        .task(id: id) {
            let id = self.id
            live.observe(wiki.store) { db in
                let b = try BookmarkQueries.bookmark(db, id: id)
                return BookmarkDetail(bookmark: b, linkedFrom: try b.map { try BookmarkQueries.linkedFrom(db, bookmark: $0) } ?? [])
            }
        }
        .onChange(of: live.value?.bookmark) { _, b in
            guard let b else { return }
            if focus != .title { title = b.title }
            if focus != .url { url = b.url }
            tags = b.tags
            if nav.editRequest == b.id { focusText = true; nav.editRequest = nil }
        }
    }

    private func content(_ b: BookmarkItem, linkedFrom: [Backlink]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "bookmark").font(.title2).foregroundStyle(.secondary)
                TextField("Title", text: $title).font(.title.bold()).textFieldStyle(.plain)
                    .focused($focus, equals: .title)
                    .onSubmit { saveTitle(b) }
                    .onChange(of: focus) { old, _ in if old == .title { saveTitle(b) } }
                    .onDisappear { saveTitle(b) }
                Spacer()
                Menu {
                    Button("Open URL") { BookmarkOpen.url(b.url) }
                    Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(b.url, forType: .string) }
                    Divider()
                    Button("Delete", role: .destructive) { delete(b) }.disabled(!app.canWrite)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding([.horizontal, .top])

            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("URL", text: $url).textFieldStyle(.plain).foregroundStyle(Color.accentColor)
                    .focused($focus, equals: .url)
                    .onSubmit { saveURL(b) }
                    .onChange(of: focus) { old, _ in if old == .url { saveURL(b) } }
                Button { BookmarkOpen.url(b.url) } label: { Label("Open", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.borderless).help("Open in the default browser")
            }
            .padding(.horizontal).padding(.top, 8)
            if let problem { Text(problem).font(.callout).foregroundStyle(.red).padding(.horizontal).padding(.top, 4) }

            TagField(tags: $tags, input: $pendingTag).padding(.horizontal).padding(.top, 8)
                .onChange(of: tags) { _, new in
                    guard new != b.tags else { return }
                    send(.updateBookmark(id: b.id, BookmarkPatch(tags: new)))
                }
            Divider().padding(.top, 8)

            GlyMarkdownEditor(text: b.description, onCommit: { text, session in
                send(.updateBookmark(id: b.id, BookmarkPatch(description: text, session: session)))
            }, initialCaret: focusText ? (b.description as NSString).length : nil)
            .frame(maxHeight: .infinity)
            Divider()
            BacklinksView(backlinks: linkedFrom, title: "Linked from", emptyText: "No text links to this URL yet")
                .padding().frame(maxWidth: .infinity, maxHeight: 180, alignment: .topLeading)
        }
    }

    private func saveTitle(_ b: BookmarkItem) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != b.title else { return }
        if trimmed.isEmpty { title = b.title; return }
        send(.updateBookmark(id: b.id, BookmarkPatch(title: trimmed)))
    }

    private func saveURL(_ b: BookmarkItem) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != b.url else { problem = nil; return }
        Task {
            if case .failure(let f) = await app.send(.updateBookmark(id: b.id, BookmarkPatch(url: trimmed)), quiet: true) {
                problem = f.message
            } else {
                problem = nil
            }
        }
    }

    private func delete(_ b: BookmarkItem) {
        Task { if case .ok = await app.send(.deleteBookmark(id: b.id)) { nav.back() } }
    }

    private func send(_ command: Command) { Task { await app.send(command) } }
}
