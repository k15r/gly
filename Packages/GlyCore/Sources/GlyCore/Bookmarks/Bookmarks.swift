import Foundation
import GRDB

/// A bookmark as read from the store (specs/bookmarks, design B1): an item of kind `bookmark`, its body the description.
public struct BookmarkItem: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var url: String
    public var description: String
    public var tags: [String]
    public var createdAt: Date
    public var modifiedAt: Date
    public var modifiedBy: String

    /// "grafana.example", for the list rows; the URL itself when it has no host (mailto).
    public var host: String { URLComponents(string: url)?.host ?? url }
}

/// New bookmark (createBookmark). An empty title becomes the URL's host.
public struct BookmarkDraft: Codable, Equatable {
    public var url: String
    public var title: String
    public var description: String
    public var tags: [String]
    public init(url: String, title: String = "", description: String = "", tags: [String] = []) {
        self.url = url; self.title = title; self.description = description; self.tags = tags
    }
}

/// Partial bookmark update (updateBookmark). `nil` = unchanged. `session` coalesces saves of one edit session of the
/// description on the bookmark's page (as for pages, design P6).
public struct BookmarkPatch: Codable, Equatable {
    public var title: String?
    public var url: String?
    public var description: String?
    public var tags: [String]?
    public var session: String?
    public init(title: String? = nil, url: String? = nil, description: String? = nil, tags: [String]? = nil, session: String? = nil) {
        self.title = title; self.url = url; self.description = description; self.tags = tags; self.session = session
    }
}

public enum BookmarkURL {
    static let schemes: Set<String> = ["http", "https", "mailto"]

    /// The stored form of a URL (B1): scheme and host lowercased, a bare host's trailing slash removed; paths stay
    /// exact. nil for anything that isn't an http, https or mailto URL.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: trimmed), let scheme = c.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        c.scheme = scheme
        if scheme == "mailto" { return c.path.isEmpty ? nil : c.string }
        guard let host = c.host, !host.isEmpty else { return nil }
        c.host = host.lowercased()
        if c.path == "/", c.query == nil, c.fragment == nil { c.path = "" }
        return c.string
    }
}

public enum BookmarkQueries {
    /// Live bookmarks by title, optionally under a tag (or below it) and matching words in title, URL, description or
    /// tags (every word must match somewhere).
    public static func list(_ db: Database, tag: TagName? = nil, text: String? = nil, limit: Int? = nil) throws -> [BookmarkItem] {
        var sql = "SELECT i.* FROM live_items i WHERE i.kind = 'bookmark'"
        var arguments: StatementArguments = []
        if let tag {
            let filter = TagFilter(tag)
            sql += " AND " + filter.sql
            arguments += filter.arguments
        }
        for word in (text ?? "").split(whereSeparator: \.isWhitespace) {
            let like = "%" + word.lowercased().replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
            sql += """
                 AND (lower(i.title) LIKE ? ESCAPE '\\' OR lower(i.url) LIKE ? ESCAPE '\\' OR lower(i.body) LIKE ? ESCAPE '\\'
                      OR i.id IN (SELECT it.item_id FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE t.name_key LIKE ? ESCAPE '\\'))
                """
            arguments += [like, like, like, like]
        }
        sql += " ORDER BY i.title COLLATE NOCASE, i.url"
        if let limit { sql += " LIMIT \(max(limit, 0))" }
        return try fetch(db, sql: sql, arguments: arguments)
    }

    public static func bookmark(_ db: Database, id: String) throws -> BookmarkItem? {
        try fetch(db, sql: "SELECT i.* FROM live_items i WHERE i.id = ? AND i.kind = 'bookmark'", arguments: [id]).first
    }

    /// The live bookmark of a URL, compared in its normalized form.
    public static func bookmark(_ db: Database, url: String) throws -> BookmarkItem? {
        try bookmarks(db, urls: [url]).values.first
    }

    /// Live bookmarks of several URLs at once (the editor's lookups), keyed by the URL as given.
    public static func bookmarks(_ db: Database, urls: [String]) throws -> [String: BookmarkItem] {
        let normalized = Dictionary(urls.compactMap { u in BookmarkURL.normalize(u).map { ($0, u) } }, uniquingKeysWith: { a, _ in a })
        guard !normalized.isEmpty else { return [:] }
        let marks = normalized.keys.map { _ in "?" }.joined(separator: ",")
        let found = try fetch(db, sql: "SELECT i.* FROM live_items i WHERE i.kind = 'bookmark' AND i.url IN (\(marks))",
                              arguments: StatementArguments(Array(normalized.keys)))
        var result: [String: BookmarkItem] = [:]
        for b in found {
            for u in urls where BookmarkURL.normalize(u) == b.url { result[u] = b }
        }
        return result
    }

    /// Pages, tasks, meetings and tag pages whose text contains the bookmark's URL, for its page ("Linked from"),
    /// each with the line around the link.
    public static func linkedFrom(_ db: Database, bookmark: BookmarkItem) throws -> [Backlink] {
        let like = "%" + bookmark.url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, kind, title, body FROM live_items WHERE id != ? AND body LIKE ? ESCAPE '\\'
            UNION ALL SELECT id, 'tag' AS kind, name AS title, page_body AS body FROM live_tags WHERE page_body LIKE ? ESCAPE '\\'
            ORDER BY title COLLATE NOCASE
            """, arguments: [bookmark.id, like, like])
        return rows.map { r in
            let body: String = r["body"], kind: String = r["kind"]
            let line = body.components(separatedBy: .newlines).first { $0.contains(bookmark.url) } ?? ""
            return Backlink(source: LinkRef(kind: kind == "tag" ? .tag : LinkRef.Kind(itemKind: kind), id: r["id"], title: r["title"]),
                            excerpt: TreeLeaf.excerpt(of: line))
        }
    }

    public static func count(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items WHERE kind = 'bookmark'") ?? 0
    }

    static func fetch(_ db: Database, sql: String, arguments: StatementArguments) throws -> [BookmarkItem] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        let tags = try TaskQueries.tagsByItem(db, ids: rows.map { $0["id"] as String })
        return rows.map { r in
            BookmarkItem(id: r["id"], title: r["title"], url: r["url"] ?? "", description: r["body"], tags: tags[r["id"]] ?? [],
                         createdAt: r["created_at"], modifiedAt: r["modified_at"], modifiedBy: r["modified_by"])
        }
    }
}

// MARK: - Commands (B2)

extension CommandHandler {
    func createBookmark(_ draft: BookmarkDraft, batch: Batch) throws -> CommandOK {
        let url = try Self.bookmarkURL(draft.url)
        // Same URL again: the existing bookmark, nothing written (spec "Same URL again").
        if let existing = try BookmarkQueries.bookmark(batch.db, url: url) {
            return CommandOK(id: existing.id, changed: false, message: "Already bookmarked as “\(existing.title)”.")
        }
        let names = try draft.tags.map(TagName.init)
        // The description is markdown like a page's text: `[[…]]` links resolve the same way.
        let (body, unresolved) = try LinkResolver.resolve(draft.description.trimmingCharacters(in: .whitespacesAndNewlines), db: batch.db)
        let id = try batch.insert("items", ["kind": "bookmark", "title": Self.bookmarkTitle(draft.title, url: url), "url": url, "body": body])
        try replaceTags(of: id, with: names, batch: batch)
        return CommandOK(id: id, unresolved: unresolved)
    }

    func updateBookmark(_ id: String, _ patch: BookmarkPatch, batch: Batch) throws -> CommandOK {
        guard let current = try BookmarkQueries.bookmark(batch.db, id: id) else { throw CommandFailure(.notFound, "Bookmark \(id) not found.") }
        var fields: Fields = [:]
        var url = current.url
        if let raw = patch.url {
            url = try Self.bookmarkURL(raw)
            if let other = try BookmarkQueries.bookmark(batch.db, url: url), other.id != id {
                throw CommandFailure(.conflict, "\(url) is already bookmarked as “\(other.title)”.")
            }
            fields["url"] = url
        }
        if let t = patch.title { fields["title"] = Self.bookmarkTitle(t, url: url) }
        var unresolved: [UnresolvedLink]?
        if let d = patch.description {
            // While typing on the page the text is kept as is; trimming would fight the editor.
            let r = try LinkResolver.resolve(patch.session == nil ? d.trimmingCharacters(in: .whitespacesAndNewlines) : d, db: batch.db)
            fields["body"] = r.text; unresolved = r.unresolved
        }
        let tagNames = try patch.tags.map { try $0.map(TagName.init) }
        var changed = !(try batch.update("items", id: id, fields)).isEmpty
        if let tagNames { changed = try replaceTags(of: id, with: tagNames, batch: batch) || changed }
        return CommandOK(id: id, changed: changed, unresolved: unresolved)
    }

    func deleteBookmark(_ id: String, batch: Batch) throws -> CommandOK {
        guard try BookmarkQueries.bookmark(batch.db, id: id) != nil else { throw CommandFailure(.notFound, "Bookmark \(id) not found.") }
        try batch.softDelete("items", id: id)
        return CommandOK(id: id)
    }

    /// A deleted bookmark can't come back while another live bookmark has its URL (the unique index, B1).
    static func checkRestorable(_ id: String, db: Database) throws {
        guard let row = try Row.fetchOne(db, sql: "SELECT url, title FROM items WHERE id = ? AND kind = 'bookmark'", arguments: [id]),
              let url: String = row["url"], let other = try BookmarkQueries.bookmark(db, url: url), other.id != id else { return }
        throw CommandFailure(.conflict, "\(url) is bookmarked again as “\(other.title)”; delete that one first.")
    }

    static func bookmarkURL(_ raw: String) throws -> String {
        guard let url = BookmarkURL.normalize(raw) else {
            throw CommandFailure(.validation, "“\(raw)” is not a web link (http, https or mailto).")
        }
        return url
    }

    static func bookmarkTitle(_ raw: String, url: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let c = URLComponents(string: url)
        return c?.host ?? c?.path ?? url
    }
}

/// The `<title>` of a fetched page, for quick capture (bookmarks B6): whitespace collapsed, common entities decoded.
public enum PageTitle {
    /// Pages are read up to this many bytes; the title is in the head.
    public static let maxBytes = 64 * 1024

    public static func extract(html: String) -> String? {
        guard let open = html.range(of: #"<title\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]),
              let close = html.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<html.endIndex) else { return nil }
        let raw = html[open.upperBound..<close.lowerBound].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let title = decodeEntities(raw)
        return title.isEmpty ? nil : title
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—"]
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semi = after.prefix(10).firstIndex(of: ";") else { out += "&"; rest = after; continue }
            let name = String(after[..<semi])
            var decoded: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = named[name.lowercased()]
            }
            if let decoded { out += decoded; rest = after[after.index(after: semi)...] } else { out += "&"; rest = after }
        }
        return out + rest
    }
}
