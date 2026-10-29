import AppKit
import Foundation
import GRDB
import Observation
import GlyCore
import GlyEditor

/// Observes one query for one view (page view, tag page view).
@MainActor
@Observable
final class Live<Value> {
    private(set) var value: Value?
    private(set) var loaded = false
    @ObservationIgnored private var cancellable: AnyDatabaseCancellable?

    func observe(_ store: ReadOnlyStore?, _ fetch: @escaping @Sendable (Database) throws -> Value) {
        guard let store else { return }
        cancellable = store.observe(ValueObservation.tracking(fetch),
                                    onError: { print("live observation: \($0)") },
                                    onChange: { [weak self] in self?.value = $0; self?.loaded = true })
    }
}

/// Pages, links and search for the views (info-pages-and-links). Reads the store directly; writes go through the agent.
@MainActor
@Observable
final class WikiModel {
    /// All live bookmarks (bookmarks B3, B5), by normalized URL for the editor's lookups; `bookmarksVersion` changes
    /// with every update, so editors restyle their links.
    private(set) var bookmarks: [BookmarkItem] = [] {
        didSet { bookmarksByURL = Dictionary(bookmarks.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a }); bookmarksVersion += 1 }
    }
    private(set) var bookmarksVersion = 0
    @ObservationIgnored private var bookmarksByURL: [String: BookmarkItem] = [:]

    @ObservationIgnored private(set) var store: ReadOnlyStore?
    @ObservationIgnored private var bookmarksObservation: AnyDatabaseCancellable?

    func attach(_ store: ReadOnlyStore?) {
        guard let store, self.store !== store else { return }
        self.store = store
        bookmarksObservation = store.observe(ValueObservation.tracking { try BookmarkQueries.list($0) },
                                             onError: { print("bookmarks observation: \($0)") },
                                             onChange: { [weak self] in self?.bookmarks = $0 })
    }

    /// The bookmark of a URL as typed or linked (compared normalized).
    func bookmark(for url: String) -> BookmarkItem? { BookmarkURL.normalize(url).flatMap { bookmarksByURL[$0] } }

    func bookmarkMark(_ url: String) -> BookmarkMark? {
        bookmark(for: url).map { BookmarkMark(title: $0.title, description: $0.description, tags: $0.tags) }
    }


    func page(_ id: String) -> PageItem? { try? store?.read { try PageQueries.page($0, id: id) } }

    // MARK: Links

    /// Current title/state of a link target, for the editor and the read view.
    func appearance(_ target: ParsedLink.Target) -> LinkAppearance {
        let lookup: (String, Bool) -> LinkAppearance = { id, isTag in
            guard let result = try? self.store?.read({ try LinkQueries.reference($0, id: id, isTag: isTag) }) else { return .missing }
            if result.1 { return .deleted(title: result.0.title, kind: result.0.kind) }
            let qualifier = isTag ? nil : self.displayNames([result.0.id])[result.0.id]?.qualifier
            return .live(title: result.0.title, kind: result.0.kind, qualifier: qualifier)
        }
        switch target {
        case .item(let id): return lookup(id, false)
        case .tag(let id): return lookup(id, true)
        case .missing: return .missing
        }
    }

    /// Display names (title + qualifier for duplicates) for items and tags (link-disambiguation K2).
    func displayNames(_ ids: [String]) -> [String: DisplayName] {
        (try? store?.read { try DisplayNames.display($0, ids: ids) }) ?? [:]
    }

    /// "Page · person/alex · edited 3 days ago"
    static func secondLine(kind: LinkRef.Kind, tags: [String], modified: Date?) -> String {
        let kindText = switch kind { case .page: "Page"; case .task: "Task"; case .tag: "Tag page"; case .meeting: "Meeting"; case .bookmark: "Bookmark" }
        let edited = modified.map { "edited " + RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) }
        return ([kindText] + (tags.isEmpty ? [] : [tags.joined(separator: ", ")]) + [edited].compactMap { $0 }).joined(separator: " · ")
    }

    /// Entries for the `[[` picker: icon, title with qualifier, second line (link-disambiguation K4).
    func suggestions(_ query: String) -> [LinkSuggestion] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let store else { return [] }
        // Prefixes (`page:`) and tag paths (`person/alex/Go…`) as in typed links (K1): exact candidates first,
        // then title search on the last segment, limited to the allowed kinds and to items under the tag path.
        let (kinds, body) = LinkResolver.parse(q)
        let slash = body.lastIndex(of: "/")
        let path = slash.map { TagName.key(for: String(body[..<$0])) }
        let term = slash.map { String(body[body.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? body
        let pathTag = slash.flatMap { try? TagName(String(body[..<$0])) }
        let (exact, hits) = (try? store.read { db -> ([LinkCandidate], [SearchHit]) in
            if term.isEmpty, let pathTag {                       // `[[person/alex/`: everything under the tag so far
                return ([LinkCandidate](), try SearchQueries.underTag(db, pathTag, kinds: kinds))
            }
            return (try LinkResolver.candidates(db, typed: q), term.isEmpty ? [] : try SearchQueries.search(db, term, limit: 12).all)
        }) ?? ([], [])
        func under(_ tags: [String]) -> Bool {
            guard let path else { return true }
            return tags.contains { let k = TagName.key(for: $0); return k == path || k.hasPrefix(path + "/") }
        }
        var refs: [(id: String, kind: LinkRef.Kind, title: String, tags: [String], modified: Date?, url: String?)] =
            exact.map { ($0.id, $0.kind, $0.title, $0.tags, nil, nil) }
        // Bookmarks come along unless a prefix asks for one kind (bookmarks B5).
        for hit in hits where kinds.contains(hit.ref.kind) || (hit.ref.kind == .bookmark && kinds.count > 1) {
            // Items must carry the path's tag (or one below it); tags must lie below the path.
            let fits = hit.ref.kind == .tag ? path.map { TagName.key(for: hit.ref.title).hasPrefix($0 + "/") } ?? true : under(hit.tags)
            guard fits, !refs.contains(where: { $0.id == hit.ref.id }) else { continue }
            refs.append((hit.ref.id, hit.ref.kind, hit.ref.title, hit.tags, hit.modifiedAt, hit.url))
        }
        refs = Array(refs.prefix(6))
        let names = displayNames(refs.map(\.id))
        return refs.map { r in
            // A bookmark goes in as a plain web link, so the text stays portable (specs/bookmarks "Insert a bookmark").
            let insert = if r.kind == .bookmark, let url = r.url { Self.webLink(label: r.title, url: url) }
                else if r.kind == .tag { LinkParser.canonical(label: r.title, tag: r.id) }
                else { LinkParser.canonical(label: r.title, item: r.id) }
            return LinkSuggestion(id: r.id, symbol: r.kind.linkSymbol, title: names[r.id]?.display ?? r.title,
                                  subtitle: Self.secondLine(kind: r.kind, tags: r.tags, modified: r.modified), insert: insert)
        }
    }

    /// `[label](url)`; brackets in the label become parentheses so the link stays one link.
    static func webLink(label: String, url: String) -> String {
        "[" + label.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")") + "](" + url + ")"
    }

    /// What an ambiguous typed link could mean, as picker entries (link-disambiguation K5).
    func candidates(_ typed: String) -> [LinkSuggestion] {
        guard let found = try? store?.read({ try LinkResolver.candidates($0, typed: typed) }), found.count > 1 else { return [] }
        let names = displayNames(found.map(\.id))
        return found.map { c in
            LinkSuggestion(id: c.id, symbol: c.kind.linkSymbol, title: names[c.id]?.display ?? c.title,
                           subtitle: Self.secondLine(kind: c.kind, tags: c.tags, modified: nil),
                           insert: c.kind == .tag ? LinkParser.canonical(label: c.title, tag: c.id) : LinkParser.canonical(label: c.title, item: c.id))
        }
    }

    /// The menu of a link without live target (trash-bin T5): missing → candidates and new page/task;
    /// deleted page/task → Restore (with when and by whom), same-titled live items, Show in Trash. nil = just open it.
    func linkMenu(_ target: ParsedLink.Target) -> LinkMenuModel? {
        switch target {
        case .missing(let typed):
            return .missing(typed: typed, candidates: candidates(typed))
        case .tag:
            return nil
        case .item(let id):
            guard let store, let (ref, deleted) = try? store.read({ try LinkQueries.reference($0, id: id, isTag: false) }), deleted,
                  let entry = try? store.read({ try TrashQueries.entry($0, id: ref.id) }) else { return nil }
            let others = (try? store.read { db in
                try LinkResolver.candidates(db, typed: (ref.kind == .task ? "task:" : "page:") + ref.title)
            })?.filter { $0.id != ref.id } ?? []
            let names = displayNames(others.map(\.id))
            let when = RelativeDateTimeFormatter().localizedString(for: entry.deletedAt, relativeTo: Date())
            return LinkMenuModel([
                [.open(title: "Restore “\(ref.title)”", symbol: "arrow.uturn.backward", url: URL(string: "\(LinkParser.scheme)://restore/\(ref.id)")!),
                 .info("deleted \(when) by \(WriterName.display(entry.deletedBy))")],
                others.map { c in
                    .replace(LinkSuggestion(id: c.id, symbol: c.kind.linkSymbol, title: "Link to “\(names[c.id]?.display ?? c.title)” instead",
                                            subtitle: Self.secondLine(kind: c.kind, tags: c.tags, modified: nil),
                                            insert: LinkParser.canonical(label: c.title, item: c.id)))
                },
                [.open(title: "Show in Trash", symbol: "trash", url: URL(string: "\(LinkParser.scheme)://trash/\(ref.id)")!)],
            ])
        }
    }

    func search(_ query: String) -> SearchResults {
        (try? store?.read { try SearchQueries.search($0, query, limit: 8) }) ?? SearchResults()
    }

    /// What a link URL opens.
    enum LinkDestination: Equatable {
        case page(String), task(String), tag(String), missing(String, create: LinkRef.Kind), web(URL)
        /// Restore a deleted page or task / show it in the Trash (trash-bin T5).
        case restore(String), trash(String)
    }

    func destination(for url: URL) -> LinkDestination? {
        guard LinkParser.isOwn(url) else { return .web(url) }
        let id = url.lastPathComponent
        switch url.host {
        case "item":
            guard let (ref, deleted) = try? store?.read({ try LinkQueries.reference($0, id: id, isTag: false) }), !deleted else { return nil }
            return ref.kind == .page ? .page(ref.id) : .task(ref.id)
        case "tag":
            guard let (ref, deleted) = try? store?.read({ try LinkQueries.reference($0, id: id, isTag: true) }), !deleted else { return nil }
            return .tag(ref.title)
        case "missing":
            return LinkParser.missingText(url).map { .missing($0, create: LinkParser.missingCreateKind(url)) }
        case "restore":
            return .restore(id)
        case "trash":
            return .trash(id)
        default:
            return nil
        }
    }
}

/// Opens links from anywhere: pages and tag pages in the main area, tasks in the editor sheet,
/// missing pages are created, web links go to the default app.
@MainActor
struct LinkOpener {
    let app: AppModel
    let wiki: WikiModel
    let nav: Navigation

    func open(_ url: URL) {
        switch wiki.destination(for: url) {
        case .page(let id): nav.go(.page(id))
        case .task(let id): nav.go(.task(id))
        case .tag(let name): nav.go(.tag(name))
        case .missing(let typed, let kind):
            guard let item = LinkResolver.newItem(for: typed, kind: kind) else { NSSound.beep(); return }
            Task { kind == .task ? await createTask(title: item.title, tags: item.tags) : await createPage(title: item.title, tags: item.tags) }
        case .web(let u): NSWorkspace.shared.open(u)
        case .restore(let id): Task { await app.send(.restore(id: id)) }      // links to it come alive in place
        case .trash(let id): nav.showTrash(selecting: id)
        case nil: NSSound.beep()
        }
    }

    /// Creates a task (every `[[title]]` elsewhere then points to it) and opens its task page.
    func createTask(title: String, tags: [String] = []) async {
        if case .ok(let r) = await app.send(.createTask(TaskDraft(title: title, tags: tags))), let id = r.id {
            nav.go(.task(id))
        }
    }

    /// Creates a page (every `[[title]]` elsewhere then points to it) and opens it.
    func createPage(title: String, tags: [String] = []) async {
        if case .ok(let r) = await app.send(.createPage(PageDraft(title: title, tags: tags))), let id = r.id {
            nav.go(.page(id))
        }
    }
}
