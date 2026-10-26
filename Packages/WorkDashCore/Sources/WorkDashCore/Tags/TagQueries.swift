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
    public let children: [TagNode]
    /// Pages tagged with exactly this path (the tag tree doubles as the page tree).
    public var pages: [PageLeaf] = []
}

/// A page listed in the tag tree; `otherTags` are the page's other tags ("also in …").
public struct PageLeaf: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let otherTags: [String]
    public init(id: String, title: String, otherTags: [String]) { self.id = id; self.title = title; self.otherTags = otherTags }
}

public enum TagQueries {
    /// Suggestions while typing a tag: next-segment completions first, then full tag names,
    /// both ordered by how often the tag is used.
    public static func autocomplete(_ db: Database, prefix typed: String, limit: Int = 10) throws -> [String] {
        let key = TagName.key(for: typed.trimmingCharacters(in: .whitespaces))
        let escaped = TagFilter.escapeLike(key)
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.name, COUNT(it.id) AS uses FROM live_tags t
            LEFT JOIN live_item_tags it ON it.tag_id = t.id
            WHERE t.archived = 0 AND t.name_key LIKE ? ESCAPE '\\'
            GROUP BY t.id ORDER BY uses DESC, t.name_key
            """, arguments: [escaped + "%"])
        var segmentCompletions: [String] = []
        var fullNames: [String] = []
        for row in rows {
            let name: String = row["name"]
            fullNames.append(name)
            // Next-segment completion: cut after the segment the user is typing.
            let rest = name.dropFirst(typed.count)
            if let slash = rest.firstIndex(of: "/") {
                let completion = String(name[..<slash])
                if !segmentCompletions.contains(completion) && !fullNames.contains(completion) { segmentCompletions.append(completion) }
            }
        }
        var result: [String] = []
        for s in segmentCompletions + fullNames where !result.contains(s) { result.append(s) }
        return Array(result.prefix(limit))
    }

    /// Tags assigned to at least one open task or live page, as a hierarchy with roll-up open-task counts.
    /// "Open" includes snoozed tasks whose snooze date has arrived (`today` = YYYY-MM-DD).
    public static func tagTree(_ db: Database, today: String) throws -> [TagNode] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT it.item_id, t.name, i.kind FROM live_item_tags it
            JOIN live_tags t ON t.id = it.tag_id
            JOIN live_items i ON i.id = it.item_id
            WHERE (i.kind = 'task' AND \(TaskQueries.effectivelyOpenSQL)) OR i.kind = 'info'
            """, arguments: ["today": today])
        // path key -> (display path, items, isTag)
        var itemsByPath: [String: Set<String>] = [:]
        var displayByPath: [String: String] = [:]
        var tagPaths = Set<String>()
        for row in rows {
            let item: String = row["item_id"]
            let name: String = row["name"]
            let isTask = (row["kind"] as String) == "task"
            let segments = name.split(separator: "/").map(String.init)
            tagPaths.insert(TagName.key(for: name))
            for depth in 1...segments.count {
                let path = segments.prefix(depth).joined(separator: "/")
                let key = TagName.key(for: path)
                if isTask { itemsByPath[key, default: []].insert(item) } else { itemsByPath[key, default: []] = itemsByPath[key] ?? [] }
                if displayByPath[key] == nil || depth == segments.count { displayByPath[key] = displayByPath[key] ?? path }
            }
        }
        let leaves = try pageLeavesByTag(db)
        func children(of parent: String?) -> [TagNode] {
            let depth = parent.map { $0.split(separator: "/").count + 1 } ?? 1
            return itemsByPath.keys
                .filter { $0.split(separator: "/").count == depth && (parent == nil || $0.hasPrefix(parent! + "/")) }
                .sorted()
                .map { key in
                    let display = displayByPath[key]!
                    return TagNode(segment: String(display.split(separator: "/").last!), path: display,
                                   isTag: tagPaths.contains(key), openCount: itemsByPath[key]!.count,
                                   children: children(of: key), pages: leaves[key] ?? [])
                }
        }
        return children(of: nil)
    }

    /// Live pages per exact tag key, each with its other tags.
    static func pageLeavesByTag(_ db: Database) throws -> [String: [PageLeaf]] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT i.id, i.title, t.name, t.name_key FROM live_items i
            JOIN live_item_tags it ON it.item_id = i.id JOIN live_tags t ON t.id = it.tag_id
            WHERE i.kind = 'info' ORDER BY i.title COLLATE NOCASE, t.name_key
            """)
        var tagsOfPage: [String: [String]] = [:]
        for r in rows { tagsOfPage[r["id"], default: []].append(r["name"]) }
        var result: [String: [PageLeaf]] = [:]
        for r in rows {
            let id: String = r["id"], name: String = r["name"]
            result[r["name_key"], default: []].append(PageLeaf(id: id, title: r["title"], otherTags: (tagsOfPage[id] ?? []).filter { $0 != name }))
        }
        return result
    }

    /// Live pages without any tag (the "Untagged" node).
    public static func untaggedPages(_ db: Database) throws -> [PageLeaf] {
        try Row.fetchAll(db, sql: """
            SELECT id, title FROM live_items WHERE kind = 'info'
              AND id NOT IN (SELECT item_id FROM live_item_tags) ORDER BY title COLLATE NOCASE
            """).map { PageLeaf(id: $0["id"], title: $0["title"], otherTags: []) }
    }
}
