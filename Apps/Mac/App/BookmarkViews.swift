import AppKit
import SwiftUI
import GlyCore

/// The bookmark editor (bookmarks B4): title, URL, description and tags. For a URL that is already bookmarked it
/// edits that bookmark (specs/bookmarks "Same URL again"); otherwise "Save" creates one.
struct BookmarkEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
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
    init(url: String = "", label: String = "", wiki: WikiModel, onDone: @escaping () -> Void) {
        let existing = url.isEmpty ? nil : wiki.bookmark(for: url)
        self.init(existing: existing, url: url, title: label, onDone: onDone)
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
                if let editing, let link = URL(string: editing.url) {
                    Button("Open") { NSWorkspace.shared.open(link) }
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

/// The Bookmarks list (bookmarks B5): search, tag filter, rows with title, host, tags and description.
/// A click opens the URL in the default browser; the context menu edits, copies or deletes.
struct BookmarksListView: View {
    @Environment(WikiModel.self) private var wiki
    @Environment(AppModel.self) private var app
    @Environment(Navigation.self) private var nav
    @State private var query = ""
    @State private var tag: String?
    @State private var adding = false
    @State private var editing: BookmarkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Bookmarks").font(.title2.bold())
                Spacer()
                TextField("Search bookmarks", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Menu {
                    Button("All tags") { tag = nil }
                    Divider()
                    ForEach(allTags, id: \.self) { t in Button(t) { tag = t } }
                } label: { Label(tag ?? "All tags", systemImage: "line.3.horizontal.decrease.circle") }
                .fixedSize()
                Button { adding = true } label: { Label("New Bookmark", systemImage: "plus") }
                    .disabled(!app.canWrite)
                    .popover(isPresented: $adding, arrowEdge: .bottom) { BookmarkEditor(wiki: wiki) { adding = false } }
            }
            .padding()
            Divider()
            let shown = filtered
            if shown.isEmpty {
                Text(wiki.bookmarks.isEmpty ? "No bookmarks yet" : "No bookmarks match").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { b in
                    BookmarkRow(bookmark: b)
                        .contentShape(Rectangle())
                        .onTapGesture { open(b) }
                        .popover(isPresented: Binding(get: { editing?.id == b.id }, set: { if !$0 { editing = nil } }), arrowEdge: .trailing) {
                            BookmarkEditor(bookmark: b) { editing = nil }
                        }
                        .contextMenu {
                            Button("Open") { open(b) }
                            Button("Edit…") { editing = b }.disabled(!app.canWrite)
                            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(b.url, forType: .string) }
                            Divider()
                            Button("Delete", role: .destructive) { Task { await app.send(.deleteBookmark(id: b.id)) } }.disabled(!app.canWrite)
                        }
                }
            }
        }
        .onAppear {
            guard let id = nav.bookmarkEditRequest else { return }
            nav.bookmarkEditRequest = nil
            editing = wiki.bookmarks.first { $0.id == id }
        }
    }

    private var allTags: [String] {
        Array(Set(wiki.bookmarks.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The tag or below it (specs/bookmarks "Filter by tag"), then every word in title, URL, description or tags.
    private var filtered: [BookmarkItem] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return wiki.bookmarks.filter { b in
            let keys = b.tags.map { TagName.key(for: $0) }
            if let tag {
                let k = TagName.key(for: tag)
                guard keys.contains(where: { $0 == k || $0.hasPrefix(k + "/") }) else { return false }
            }
            let haystack = ([b.title, b.url, b.description] + keys).joined(separator: "\n").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private func open(_ b: BookmarkItem) { if let url = URL(string: b.url) { NSWorkspace.shared.open(url) } }
}

struct BookmarkRow: View {
    let bookmark: BookmarkItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bookmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bookmark.title).font(.headline).lineLimit(1)
                    Text(bookmark.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                let line = TreeLeaf.excerpt(of: bookmark.description)
                if !line.isEmpty { Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                if !bookmark.tags.isEmpty {
                    HStack(spacing: 4) { ForEach(bookmark.tags, id: \.self) { TagChip(name: $0) } }.padding(.top, 1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .help(bookmark.url)
    }
}
