import AppKit
import Foundation
import GRDB
import Observation
import WorkDashCore
import WorkDashEditor

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
    private(set) var pages: [PageItem] = []
    private(set) var untagged: [TreeLeaf] = []
    var pageTagFilter: TagName? { didSet { observePages() } }

    @ObservationIgnored private(set) var store: ReadOnlyStore?
    @ObservationIgnored private var pagesObservation: AnyDatabaseCancellable?
    @ObservationIgnored private var untaggedObservation: AnyDatabaseCancellable?

    func attach(_ store: ReadOnlyStore?) {
        guard let store, self.store !== store else { return }
        self.store = store
        observePages()
        untaggedObservation = store.observe(ValueObservation.tracking { try TagQueries.untaggedItems($0) },
                                            onError: { print("untagged observation: \($0)") },
                                            onChange: { [weak self] in self?.untagged = $0 })
    }

    private func observePages() {
        guard let store else { return }
        let tag = pageTagFilter
        pagesObservation = store.observe(ValueObservation.tracking { try PageQueries.list($0, tag: tag) },
                                         onError: { print("pages observation: \($0)") },
                                         onChange: { [weak self] in self?.pages = $0 })
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
        let kindText = switch kind { case .page: "Page"; case .task: "Task"; case .tag: "Tag page" }
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
        var refs: [(id: String, kind: LinkRef.Kind, title: String, tags: [String], modified: Date?)] =
            exact.map { ($0.id, $0.kind, $0.title, $0.tags, nil) }
        for hit in hits where kinds.contains(hit.ref.kind) {
            // Items must carry the path's tag (or one below it); tags must lie below the path.
            let fits = hit.ref.kind == .tag ? path.map { TagName.key(for: hit.ref.title).hasPrefix($0 + "/") } ?? true : under(hit.tags)
            guard fits, !refs.contains(where: { $0.id == hit.ref.id }) else { continue }
            refs.append((hit.ref.id, hit.ref.kind, hit.ref.title, hit.tags, hit.modifiedAt))
        }
        refs = Array(refs.prefix(6))
        let names = displayNames(refs.map(\.id))
        return refs.map { r in
            let insert = r.kind == .tag ? LinkParser.canonical(label: r.title, tag: r.id) : LinkParser.canonical(label: r.title, item: r.id)
            return LinkSuggestion(id: r.id, symbol: r.kind.linkSymbol, title: names[r.id]?.display ?? r.title,
                                  subtitle: Self.secondLine(kind: r.kind, tags: r.tags, modified: r.modified), insert: insert)
        }
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

    func search(_ query: String) -> SearchResults {
        (try? store?.read { try SearchQueries.search($0, query, limit: 8) }) ?? SearchResults()
    }

    /// What a link URL opens.
    enum LinkDestination: Equatable {
        case page(String), task(String), tag(String), missing(String), web(URL)
    }

    func destination(for url: URL) -> LinkDestination? {
        guard url.scheme == LinkParser.scheme else { return .web(url) }
        let id = url.lastPathComponent
        switch url.host {
        case "item":
            guard let (ref, deleted) = try? store?.read({ try LinkQueries.reference($0, id: id, isTag: false) }), !deleted else { return nil }
            return ref.kind == .page ? .page(ref.id) : .task(ref.id)
        case "tag":
            guard let (ref, deleted) = try? store?.read({ try LinkQueries.reference($0, id: id, isTag: true) }), !deleted else { return nil }
            return .tag(ref.title)
        case "missing":
            return .missing(id.removingPercentEncoding ?? id)
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
        case .missing(let typed):
            guard let page = LinkResolver.newPage(for: typed) else { NSSound.beep(); return }
            Task { await createPage(title: page.title, tags: page.tags) }
        case .web(let u): NSWorkspace.shared.open(u)
        case nil: NSSound.beep()
        }
    }

    /// Creates a page (every `[[title]]` elsewhere then points to it) and opens it.
    func createPage(title: String, tags: [String] = []) async {
        if case .ok(let r) = await app.send(.createPage(PageDraft(title: title, tags: tags))), let id = r.id {
            nav.go(.page(id))
        }
    }
}
