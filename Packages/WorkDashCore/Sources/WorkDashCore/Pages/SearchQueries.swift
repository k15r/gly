import Foundation
import GRDB

/// One search result (specs/search).
public struct SearchHit: Equatable, Identifiable {
    public var id: String { ref.id }
    public let ref: LinkRef
    /// Text around the match; empty when only the title matched.
    public let excerpt: String
    public var tags: [String] = []
    public var modifiedAt: Date?
}

/// Results grouped by kind; each group ordered by relevance (bm25 is not comparable across kinds).
public struct SearchResults: Equatable {
    public var pages: [SearchHit] = []
    public var tasks: [SearchHit] = []
    public var tags: [SearchHit] = []
    /// Meetings with notes (meeting-pages), found by title and notes text.
    public var meetings: [SearchHit] = []
    public init() {}
    public var isEmpty: Bool { pages.isEmpty && tasks.isEmpty && tags.isEmpty && meetings.isEmpty }
    public var all: [SearchHit] { pages + tasks + meetings + tags }
}

public enum SearchQueries {
    /// FTS5 query for user input: every word quoted, the last one as a prefix. nil for empty input.
    public static func ftsQuery(_ input: String) -> String? {
        let words = input.split(whereSeparator: { $0.isWhitespace }).map { $0.replacingOccurrences(of: "\"", with: "") }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.enumerated().map { i, w in i == words.count - 1 ? "\"\(w)\"*" : "\"\(w)\"" }.joined(separator: " ")
    }

    public static func search(_ db: Database, _ input: String, kinds: Set<LinkRef.Kind> = [.page, .task, .tag, .meeting], limit: Int = 20) throws -> SearchResults {
        guard let match = ftsQuery(input) else { return SearchResults() }
        var results = SearchResults()
        for kind in kinds {
            // Deleted rows aren't in the index (DerivedIndex); only archived tags need filtering.
            let (ftsKind, extra): (String, String)
            switch kind {
            case .page: (ftsKind, extra) = ("info", "")
            case .task: (ftsKind, extra) = ("task", "")
            case .tag: (ftsKind, extra) = ("tag", " AND owner_id NOT IN (SELECT id FROM tags WHERE archived = 1)")
            // Annotation rows that only carry a blocking override have no notes and aren't results.
            case .meeting: (ftsKind, extra) = ("event_note", " AND owner_id IN (SELECT id FROM live_items WHERE kind = 'event_note' AND body != '')")
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT owner_id, title, snippet(search_index, 4, '', '', '…', 12) AS excerpt
                FROM search_index
                WHERE search_index MATCH ? AND kind = ?\(extra)
                ORDER BY bm25(search_index, 0, 0, 0, 10.0, 1.0)
                LIMIT ?
                """, arguments: [match, ftsKind, limit])
            let hits = rows.map { r in
                SearchHit(ref: LinkRef(kind: kind, id: r["owner_id"], title: r["title"]),
                          excerpt: (r["excerpt"] as String? ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            }
            switch kind {
            case .page: results.pages = hits
            case .task: results.tasks = hits
            case .tag: results.tags = hits
            case .meeting: results.meetings = hits
            }
        }
        results.pages = try enrich(db, results.pages); results.tasks = try enrich(db, results.tasks); results.tags = try enrich(db, results.tags)
        results.meetings = try enrich(db, results.meetings)
        return results
    }

    /// What lives under a tag, for the link picker after `[[person/alex/` (no title typed yet): live pages and open tasks
    /// carrying the tag or a tag below it, most recently changed first, then the tags below it.
    public static func underTag(_ db: Database, _ tag: TagName, kinds: Set<LinkRef.Kind> = [.page, .task, .tag], limit: Int = 8) throws -> [SearchHit] {
        let filter = TagFilter(tag)
        var hits = try Row.fetchAll(db, sql: """
            SELECT i.id, i.kind, i.title FROM live_items i
            WHERE ((i.kind = 'info' AND ?) OR (i.kind = 'task' AND i.status IN ('open', 'snoozed') AND ?)) AND \(filter.sql)
            ORDER BY i.modified_at DESC LIMIT ?
            """, arguments: [kinds.contains(.page), kinds.contains(.task)] + filter.arguments + [limit]).map { r in
                SearchHit(ref: LinkRef(kind: LinkRef.Kind(itemKind: r["kind"]), id: r["id"], title: r["title"]), excerpt: "")
            }
        if kinds.contains(.tag), hits.count < limit {
            hits += try Row.fetchAll(db, sql: "SELECT id, name FROM live_tags WHERE name_key LIKE ? ESCAPE '\\' ORDER BY name_key LIMIT ?",
                                     arguments: [TagFilter.descendantPattern(tag), limit - hits.count]).map { r in
                SearchHit(ref: LinkRef(kind: .tag, id: r["id"], title: r["name"]), excerpt: "")
            }
        }
        return try enrich(db, hits)
    }

    /// Tags and last change for the second line of results (link-disambiguation K4).
    static func enrich(_ db: Database, _ hits: [SearchHit]) throws -> [SearchHit] {
        let ids = hits.map(\.ref.id)
        guard !ids.isEmpty else { return hits }
        let tags = try TaskQueries.tagsByItem(db, ids: ids)
        let marks = ids.map { _ in "?" }.joined(separator: ",")
        var modified: [String: Date] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, modified_at FROM items WHERE id IN (\(marks)) UNION ALL SELECT id, modified_at FROM tags WHERE id IN (\(marks))",
                                  arguments: StatementArguments(ids + ids)) { modified[r["id"]] = r["modified_at"] }
        return hits.map { var h = $0; h.tags = tags[h.ref.id] ?? []; h.modifiedAt = modified[h.ref.id]; return h }
    }
}
