import Foundation
import GRDB

/// An info page as read from the store.
public struct PageItem: Equatable, Identifiable {
    public let id: String
    public var title: String
    public var body: String
    public var tags: [String]
    public var createdAt: Date
    public var modifiedAt: Date
    public var modifiedBy: String
}

/// Something a link or backlink points at: a page, a task or a tag.
public struct LinkRef: Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable {
        case page, task, tag
        /// A meeting's notes document (meeting-pages N7); not offered by the `[[` picker.
        case meeting
        /// A bookmark (bookmarks B2); the picker inserts it as a web link.
        case bookmark

        /// The kind of an `items` row (`info`, `task`, `event_note`, `bookmark`).
        public init(itemKind: String) {
            switch itemKind {
            case "info": self = .page
            case "event_note": self = .meeting
            case "bookmark": self = .bookmark
            default: self = .task
            }
        }
    }
    public let kind: Kind
    public let id: String
    public let title: String
    public init(kind: Kind, id: String, title: String) { self.kind = kind; self.id = id; self.title = title }
}

public enum PageQueries {
    /// All live pages, most recently modified first, optionally filtered by tag (including descendants).
    public static func list(_ db: Database, tag: TagName? = nil) throws -> [PageItem] {
        var sql = "SELECT i.* FROM live_items i WHERE i.kind = 'info'"
        var arguments: StatementArguments = []
        if let tag {
            let filter = TagFilter(tag)
            sql += " AND " + filter.sql
            arguments = filter.arguments
        }
        sql += " ORDER BY i.modified_at DESC, i.title"
        return try fetchPages(db, sql: sql, arguments: arguments)
    }

    public static func page(_ db: Database, id: String) throws -> PageItem? {
        try fetchPages(db, sql: "SELECT i.* FROM live_items i WHERE i.id = ? AND i.kind = 'info'", arguments: [id]).first
    }

    static func fetchPages(_ db: Database, sql: String, arguments: StatementArguments) throws -> [PageItem] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        let tags = try TaskQueries.tagsByItem(db, ids: rows.map { $0["id"] as String })
        return rows.map { r in
            PageItem(id: r["id"], title: r["title"], body: r["body"], tags: tags[r["id"]] ?? [],
                     createdAt: r["created_at"], modifiedAt: r["modified_at"], modifiedBy: r["modified_by"])
        }
    }
}

/// A link in a source text, with its target's current state (specs/links).
public struct OutgoingLink: Equatable {
    public enum Target: Equatable {
        case live(LinkRef)
        /// The target exists but was deleted ("link target deleted").
        case deleted(LinkRef)
        /// `[[Title]]` without a (unique) target; also canonical links to ids that don't exist.
        case missing(String)
    }
    public let range: NSRange
    public let target: Target
}

/// One source that links to a target, with an excerpt around the (first) link.
public struct Backlink: Equatable, Identifiable {
    public var id: String { source.id }
    public let source: LinkRef
    public let excerpt: String
}

public enum LinkQueries {
    /// Links in the text of an item or tag, resolved to their targets' current titles and states.
    public static func outgoing(_ db: Database, sourceTable: String, sourceID: String) throws -> [OutgoingLink] {
        let column = sourceTable == "tags" ? "page_body" : "body"
        guard let text = try String.fetchOne(db, sql: "SELECT \(column) FROM \(sourceTable) WHERE id = ?", arguments: [sourceID]) else { return [] }
        return try LinkParser.links(in: text).map { link in
            switch link.target {
            case .missing(let title): return OutgoingLink(range: link.range, target: .missing(title))
            case .item(let id), .tag(let id):
                let isTag: Bool = { if case .tag = link.target { return true }; return false }()
                guard let (ref, deleted) = try reference(db, id: id, isTag: isTag) else { return OutgoingLink(range: link.range, target: .missing(link.label)) }
                return OutgoingLink(range: link.range, target: deleted ? .deleted(ref) : .live(ref))
            }
        }
    }

    /// Current title and deletion state of an item or tag.
    public static func reference(_ db: Database, id: String, isTag: Bool) throws -> (LinkRef, Bool)? {
        if isTag {
            guard let r = try Row.fetchOne(db, sql: "SELECT id, name, deleted_at FROM tags WHERE id = ? COLLATE NOCASE", arguments: [id]) else { return nil }
            return (LinkRef(kind: .tag, id: r["id"], title: r["name"]), (r["deleted_at"] as Date?) != nil)
        }
        let sql = "SELECT id, kind, title, deleted_at FROM items WHERE id = ? COLLATE NOCASE"
        guard let r = try Row.fetchOne(db, sql: sql, arguments: [id]) else { return nil }
        return (LinkRef(kind: LinkRef.Kind(itemKind: r["kind"]), id: r["id"], title: r["title"]), (r["deleted_at"] as Date?) != nil)
    }

    /// Live pages, tasks and tag pages whose text links to the item or tag `targetID`.
    public static func backlinks(_ db: Database, to targetID: String, isTag: Bool = false) throws -> [Backlink] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT l.source_table, l.source_id, MIN(l.range_location) AS loc, MIN(l.range_length) AS len FROM link_index l
            LEFT JOIN items i ON l.source_table = 'items' AND i.id = l.source_id
            LEFT JOIN tags t ON l.source_table = 'tags' AND t.id = l.source_id
            WHERE l.target_kind = ? AND l.target_id = ? AND COALESCE(i.deleted_at, t.deleted_at) IS NULL
              AND (i.id IS NOT NULL OR t.id IS NOT NULL)
            GROUP BY l.source_table, l.source_id
            """, arguments: [isTag ? "tag" : "item", targetID.uppercased()])
        var result: [Backlink] = []
        for r in rows {
            let table: String = r["source_table"], id: String = r["source_id"]
            guard let (ref, _) = try reference(db, id: id, isTag: table == "tags") else { continue }
            let column = table == "tags" ? "page_body" : "body"
            let text = try String.fetchOne(db, sql: "SELECT \(column) FROM \(table) WHERE id = ?", arguments: [id]) ?? ""
            result.append(Backlink(source: ref, excerpt: excerpt(text, around: NSRange(location: r["loc"], length: r["len"]))))
        }
        return result.sorted { ($0.source.kind.rawValue, $0.source.title) < ($1.source.kind.rawValue, $1.source.title) }
    }

    /// The paragraph containing `range`, as plain text, shortened around the link.
    static func excerpt(_ text: String, around range: NSRange, maxLength: Int = 140) -> String {
        let ns = text as NSString
        guard NSMaxRange(range) <= ns.length else { return "" }
        let paragraph = ns.paragraphRange(for: range)
        let before = LinkParser.plainText(ns.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location)))
        let link = LinkParser.plainText(ns.substring(with: range))
        let after = LinkParser.plainText(ns.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(paragraph) - NSMaxRange(range))))
        let budget = max(0, (maxLength - link.count) / 2)
        let head = before.count > budget ? "…" + before.suffix(budget) : before
        let tail = after.count > budget ? after.prefix(budget) + "…" : after
        return (head + link + tail).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Content of a tag page (specs/tag-pages "Tag page content").
public struct TagPageData: Equatable {
    public let name: String
    /// nil for a group node without a tag row of its own yet (e.g. `person`).
    public let tagID: String?
    public let body: String
    public let openTasks: [TaskItem]
    public let pages: [PageItem]
    /// Meetings with notes tagged with it or below it, most recently edited first (meeting-pages).
    public var meetings: [LinkRef] = []
    public let finishedTasks: [TaskItem]
}

public enum TagPageQueries {
    public static func page(_ db: Database, name: TagName, today: LocalDay) throws -> TagPageData {
        let tagRow = try Row.fetchOne(db, sql: "SELECT id, name, page_body FROM live_tags WHERE name_key = ?", arguments: [name.key])
        let open = try TaskQueries.taskList(db, mode: .open, today: today, tag: name)
        let done = try TaskQueries.taskList(db, mode: .done, today: today, tag: name)
        let dropped = try TaskQueries.taskList(db, mode: .dropped, today: today, tag: name)
        let finished = (done + dropped).sorted { ($0.completedAt ?? $0.modifiedAt) > ($1.completedAt ?? $1.modifiedAt) }
        let filter = TagFilter(name)
        let meetings = try Row.fetchAll(db, sql: """
            SELECT i.id, i.title FROM live_items i WHERE i.kind = 'event_note' AND i.body != '' AND \(filter.sql) ORDER BY i.modified_at DESC
            """, arguments: filter.arguments).map { LinkRef(kind: .meeting, id: $0["id"], title: $0["title"]) }
        return TagPageData(name: tagRow?["name"] ?? name.display, tagID: tagRow?["id"], body: tagRow?["page_body"] ?? "",
                           openTasks: open, pages: try PageQueries.list(db, tag: name), meetings: meetings, finishedTasks: finished)
    }
}
