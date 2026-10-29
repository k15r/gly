import Foundation

/// Counts over a result list (item-browser I2): computed from the results themselves, so the tag tree and the result
/// count agree.
public enum BrowseFacets {
    /// Per tag key, how many items carry the tag or a tag below it (ancestors included: `person/alex` counts for `person`).
    public static func tagCounts(_ items: [BrowseItem]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items {
            var paths = Set<String>()
            for tag in item.tags {
                let segments = TagName.key(for: tag).split(separator: "/")
                for depth in 1...max(segments.count, 1) { paths.insert(segments.prefix(depth).joined(separator: "/")) }
            }
            for p in paths { counts[p, default: 0] += 1 }
        }
        return counts
    }

    /// Items without any tag ("Untagged" in the tag tree).
    public static func untaggedCount(_ items: [BrowseItem]) -> Int { items.filter { $0.tags.isEmpty }.count }
}

/// How results are grouped (item-browser I5).
public enum ItemGrouping: String, Codable, CaseIterable, Sendable {
    case none, kind, due, status, priority, effort, changed, tag

    /// Groupings that only sort tasks apart (the others land in "Not a task").
    public var tasksOnly: Bool { [.due, .status, .priority, .effort].contains(self) }
}

public struct ItemGroup: Equatable, Identifiable {
    public let id: String
    public let title: String
    public var items: [BrowseItem]
    /// Shown closed at first (finished tasks in tag views).
    public var collapsed = false
}

public enum BrowseGroups {
    public static func group(_ items: [BrowseItem], by grouping: ItemGrouping, query: ItemQuery, sort: ItemSort,
                             today: LocalDay, calendar: Calendar = .current) -> [ItemGroup] {
        func groups(_ order: [(String, String)], _ key: (BrowseItem) -> [String]) -> [ItemGroup] {
            var byKey: [String: [BrowseItem]] = [:]
            for item in items { for k in key(item) { byKey[k, default: []].append(item) } }
            return order.compactMap { id, title in byKey[id].map { ItemGroup(id: id, title: title, items: $0) } }
        }
        switch grouping {
        case .none:
            return items.isEmpty ? [] : [ItemGroup(id: "all", title: "", items: items)]
        case .kind:
            var result = groups([("open", "Open tasks"), ("page", "Pages"), ("meeting", "Meetings"), ("bookmark", "Bookmarks"),
                                 ("finished", "Finished tasks")]) { item in
                if let t = item.task { return [[.open, .snoozed].contains(t.status) ? "open" : "finished"] }
                return [item.kind.rawValue]
            }
            for i in result.indices {
                if result[i].id == "finished" { result[i].collapsed = true }
                // In task-list order (tag views), each kind keeps its own order (specs/tag-pages "Tag page content").
                if sort == .taskOrder {
                    switch result[i].id {
                    case "page", "meeting": result[i].items.sort { $0.modifiedAt > $1.modifiedAt }
                    case "bookmark": result[i].items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    case "finished": result[i].items.sort { ($0.task?.completedAt ?? $0.modifiedAt) > ($1.task?.completedAt ?? $1.modifiedAt) }
                    default: break
                    }
                }
            }
            return result
        case .due:
            let week = today.adding(days: 6, calendar: calendar).description, now = today.description
            return groups([("overdue", "Overdue"), ("earlier", "Earlier"), ("today", "Today"), ("week", "This week"),
                           ("later", "Later"), ("none", "No due date")]) { item in
                guard let t = item.task, let day = t.due?.day else { return ["none"] }
                if day < now { return [[.open, .snoozed].contains(t.status) ? "overdue" : "earlier"] }
                return [day == now ? "today" : day <= week ? "week" : "later"]
            }
        case .status:
            return groups([("open", "Open"), ("snoozed", "Snoozed"), ("done", "Done"), ("dropped", "Dropped"), ("other", "Not a task")]) { item in
                [item.task?.status.rawValue ?? "other"]
            }
        case .priority:
            return groups(Priority.allCases.reversed().map { ($0.rawValue, $0 == .none ? "No priority" : $0.rawValue.capitalized) }
                          + [("other", "Not a task")]) { item in [item.task?.priority.rawValue ?? "other"] }
        case .effort:
            return groups(Effort.allCases.map { ($0.rawValue, $0.rawValue) } + [("none", "No effort"), ("other", "Not a task")]) { item in
                guard let t = item.task else { return ["other"] }
                return [t.effort?.rawValue ?? "none"]
            }
        case .changed:
            let start = today.interval(in: calendar).start
            let yesterday = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            let week = calendar.date(byAdding: .day, value: -7, to: start) ?? start
            return groups([("today", "Today"), ("yesterday", "Yesterday"), ("week", "Last 7 days"), ("earlier", "Earlier")]) { item in
                let m = item.modifiedAt
                return [m >= start ? "today" : m >= yesterday ? "yesterday" : m >= week ? "week" : "earlier"]
            }
        case .tag:
            return tagGroups(items, query: query)
        }
    }

    /// The next level below the single filtered tag, else top-level tags; an item appears in each of its groups.
    /// Items tagged exactly with the filtered tag form a group of that tag, items without a matching tag "Untagged".
    static func tagGroups(_ items: [BrowseItem], query: ItemQuery) -> [ItemGroup] {
        let base = query.tags.count == 1 ? TagName.key(for: query.tags[0]) : nil
        var titles: [String: String] = [:]
        var byKey: [String: [BrowseItem]] = [:]
        for item in items {
            var keys = Set<String>()
            for tag in item.tags {
                let key = TagName.key(for: tag), segments = tag.split(separator: "/").map(String.init)
                if let base {
                    guard key == base || key.hasPrefix(base + "/") else { continue }
                    let depth = base.split(separator: "/").count
                    let display = segments.prefix(min(depth + 1, segments.count)).joined(separator: "/")
                    keys.insert(TagName.key(for: display)); titles[TagName.key(for: display)] = display
                } else if let first = segments.first {
                    keys.insert(TagName.key(for: first)); titles[TagName.key(for: first)] = first
                }
            }
            if keys.isEmpty { keys = ["\u{0}untagged"] }
            for k in keys { byKey[k, default: []].append(item) }
        }
        return byKey.keys.sorted().map { k in
            ItemGroup(id: k, title: k == "\u{0}untagged" ? "Untagged" : titles[k] ?? k, items: byKey[k]!)
        }.sorted { a, b in a.id == "\u{0}untagged" ? false : b.id == "\u{0}untagged" ? true : a.id < b.id }
    }
}
