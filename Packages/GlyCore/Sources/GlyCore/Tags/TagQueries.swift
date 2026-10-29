import Foundation
import GRDB

/// SQL condition selecting items that carry `tag` or any tag below it (specs/tags "Filter tasks by tag").
/// Compiled as an uncorrelated `IN` subquery (foundation-spikes D3): never a per-row EXISTS.
public struct TagFilter {
    public let sql: String
    public let arguments: StatementArguments

    /// - Parameter itemColumn: the item id column of the outer query, e.g. `i.id`.
    /// LIKE pattern matching everything strictly below `tag` (`\` is the escape character).
    public static func descendantPattern(_ tag: TagName) -> String { escapeLike(tag.key) + "/%" }

    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    public init(_ tag: TagName, itemColumn: String = "i.id") {
        sql = """
            \(itemColumn) IN (SELECT it.item_id FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id
                              WHERE t.name_key = ? OR t.name_key LIKE ? ESCAPE '\\')
            """
        arguments = [tag.key, TagFilter.descendantPattern(tag)]
    }
}

/// A node of the tag hierarchy shown in the tag list (specs/tags "Tag list").
public struct TagNode: Equatable, Identifiable {
    public var id: String { path }
    /// Last segment, e.g. `alex`.
    public let segment: String
    /// Full path, e.g. `person/alex` (display casing).
    public let path: String
    /// Whether a tag with exactly this path exists (false for pure group nodes like `person`).
    public let isTag: Bool
    /// Open tasks tagged with this path or anything below it.
    public let openCount: Int
    public var children: [TagNode]
    /// Open tasks, then pages, tagged with exactly this path (the tag tree shows everything tagged).
    public var items: [TreeLeaf] = []
}

/// An item listed in the tag tree; `otherTags` are its other tags ("also in …").
/// Annotated appointments will be a further kind later.
public struct TreeLeaf: Equatable, Identifiable {
    public var id: String { itemID }
    public let kind: LinkRef.Kind
    public let itemID: String
    public let title: String
    public let otherTags: [String]
    /// Tasks only: snoozed (shown marked).
    public let snoozed: Bool
    /// The start of the text as one plain line (tells same-titled items apart in the tree).
    public let excerpt: String
    public init(kind: LinkRef.Kind, id: String, title: String, otherTags: [String], snoozed: Bool = false, excerpt: String = "") {
        self.kind = kind; self.itemID = id; self.title = title; self.otherTags = otherTags; self.snoozed = snoozed; self.excerpt = excerpt
    }

    /// Plain text (links as labels, markdown markers dropped), whitespace collapsed, shortened to `maxLength`.
    public static func excerpt(of body: String, maxLength: Int = 120) -> String {
        let lines = LinkParser.plainText(body).components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: #"^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|>\s*)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(\*\*|__|~~|`)"#, with: "", options: .regularExpression)
        }
        let text = lines.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.count > maxLength else { return text }
        let cut = text.prefix(maxLength - 1)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut          // don't end mid-word
        return atWord.trimmingCharacters(in: .whitespaces) + "…"
    }
}

public enum TagQueries {
    /// All live tags as a hierarchy with roll-up open-task counts (tags without open items included, so every tag
    /// can be colored, renamed or deleted).
    /// "Open" includes snoozed tasks, as in the task list (snoozed = not now, still open).
    public static func tagTree(_ db: Database, today: String) throws -> [TagNode] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT it.item_id, t.name, i.kind FROM live_item_tags it
            JOIN live_tags t ON t.id = it.tag_id
            JOIN live_items i ON i.id = it.item_id
            WHERE (i.kind = 'task' AND i.status IN ('open', 'snoozed')) OR i.kind IN ('info', 'bookmark') OR (i.kind = 'event_note' AND i.body != '')
            UNION ALL
            SELECT NULL, t.name, NULL FROM live_tags t
            """)
        // path key -> (display path, items, isTag)
        var itemsByPath: [String: Set<String>] = [:]
        var displayByPath: [String: String] = [:]
        var tagPaths = Set<String>()
        for row in rows {
            let item: String? = row["item_id"]
            let name: String = row["name"]
            let isTask = (row["kind"] as String?) == "task"
            let segments = name.split(separator: "/").map(String.init)
            tagPaths.insert(TagName.key(for: name))
            for depth in 1...segments.count {
                let path = segments.prefix(depth).joined(separator: "/")
                let key = TagName.key(for: path)
                if isTask, let item { itemsByPath[key, default: []].insert(item) } else { itemsByPath[key, default: []] = itemsByPath[key] ?? [] }
                if displayByPath[key] == nil || depth == segments.count { displayByPath[key] = displayByPath[key] ?? path }
            }
        }
        let leaves = try leavesByTag(db)
        func children(of parent: String?) -> [TagNode] {
            let depth = parent.map { $0.split(separator: "/").count + 1 } ?? 1
            return itemsByPath.keys
                .filter { $0.split(separator: "/").count == depth && (parent == nil || $0.hasPrefix(parent! + "/")) }
                .sorted()
                .map { key in
                    let display = displayByPath[key]!
                    return TagNode(segment: String(display.split(separator: "/").last!), path: display,
                                   isTag: tagPaths.contains(key), openCount: itemsByPath[key]!.count,
                                   children: children(of: key), items: leaves[key] ?? [])
                }
        }
        return children(of: nil)
    }

    /// Open tasks (task-list order), live pages (by title), meetings with notes, then bookmarks (by title), per exact tag key, each with its other tags.
    static func leavesByTag(_ db: Database) throws -> [String: [TreeLeaf]] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT i.id, i.kind, i.title, i.status, i.body, t.name, t.name_key FROM live_items i
            JOIN live_item_tags it ON it.item_id = i.id JOIN live_tags t ON t.id = it.tag_id
            WHERE (i.kind = 'task' AND i.status IN ('open', 'snoozed')) OR i.kind IN ('info', 'bookmark') OR (i.kind = 'event_note' AND i.body != '')
            ORDER BY i.kind DESC, CASE WHEN i.kind IN ('info', 'bookmark') THEN i.title END COLLATE NOCASE, \(TaskQueries.openOrderSQL), t.name_key
            """)
        var tagsOfItem: [String: [String]] = [:]
        for r in rows { tagsOfItem[r["id"], default: []].append(r["name"]) }
        var result: [String: [TreeLeaf]] = [:]
        for r in rows {
            let id: String = r["id"], name: String = r["name"]
            result[r["name_key"], default: []].append(TreeLeaf(
                kind: LinkRef.Kind(itemKind: r["kind"]), id: id, title: r["title"],
                otherTags: (tagsOfItem[id] ?? []).filter { $0 != name }, snoozed: (r["status"] as String?) == "snoozed",
                excerpt: TreeLeaf.excerpt(of: r["body"] ?? "")))
        }
        return result
    }

    /// Open tasks, live pages, meetings with notes and bookmarks without any tag (the "Untagged" node): tasks first.
    public static func untaggedItems(_ db: Database) throws -> [TreeLeaf] {
        try Row.fetchAll(db, sql: """
            SELECT i.id, i.kind, i.title, i.status, i.body FROM live_items i
            WHERE ((i.kind = 'task' AND i.status IN ('open', 'snoozed')) OR i.kind IN ('info', 'bookmark') OR (i.kind = 'event_note' AND i.body != ''))
              AND i.id NOT IN (SELECT item_id FROM live_item_tags)
            ORDER BY i.kind DESC, CASE WHEN i.kind IN ('info', 'bookmark') THEN i.title END COLLATE NOCASE, \(TaskQueries.openOrderSQL)
            """).map { r in
                TreeLeaf(kind: LinkRef.Kind(itemKind: r["kind"]), id: r["id"], title: r["title"],
                         otherTags: [], snoozed: (r["status"] as String?) == "snoozed", excerpt: TreeLeaf.excerpt(of: r["body"] ?? ""))
            }
    }
}
