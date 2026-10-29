import Foundation

/// A view of the item browser (item-browser I3): a preset, a saved view or a tag's view. The query is stored in its
/// text form, so saved views survive changes of `ItemQuery`'s fields.
public struct ItemView: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var symbol: String
    public var query: ItemQuery
    public var grouping: ItemGrouping
    public var sort: ItemSort

    public init(id: String, name: String, symbol: String, query: ItemQuery, grouping: ItemGrouping = .none, sort: ItemSort) {
        self.id = id; self.name = name; self.symbol = symbol; self.query = query; self.grouping = grouping; self.sort = sort
    }

    enum CodingKeys: String, CodingKey { case id, name, symbol, query, grouping, sort }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "line.3.horizontal.decrease.circle"
        query = ItemQuery.parse(try c.decode(String.self, forKey: .query))
        grouping = (try? c.decode(ItemGrouping.self, forKey: .grouping)) ?? .none
        sort = (try? c.decode(ItemSort.self, forKey: .sort)) ?? .changed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(symbol, forKey: .symbol)
        try c.encode(query.description, forKey: .query); try c.encode(grouping, forKey: .grouping); try c.encode(sort, forKey: .sort)
    }

    public var isPreset: Bool { Self.presets.contains { $0.id == id } }
    public var isTagView: Bool { id.hasPrefix("tag:") }

    // MARK: Presets (specs/item-browser "Item browser and preset views")

    public static let all = ItemView(id: "all", name: "All items", symbol: "tray.full", query: ItemQuery(), sort: .changed)
    public static let tasks = ItemView(id: "tasks", name: "Tasks", symbol: "checklist",
                                       query: ItemQuery.parse("is:task status:open status:snoozed"), sort: .taskOrder)
    public static let pages = ItemView(id: "pages", name: "Pages", symbol: "doc.text", query: ItemQuery.parse("is:page"), sort: .changed)
    public static let bookmarks = ItemView(id: "bookmarks", name: "Bookmarks", symbol: "bookmark", query: ItemQuery.parse("is:bookmark"), sort: .title)
    public static let meetings = ItemView(id: "meetings", name: "Meetings", symbol: "calendar", query: ItemQuery.parse("is:meeting"), sort: .changed)
    public static let presets = [all, tasks, pages, bookmarks, meetings]

    /// A tag's view (specs/tag-pages "Tag page content"): everything under the tag, grouped by kind.
    public static func tag(_ name: String) -> ItemView {
        ItemView(id: "tag:" + TagName.key(for: name), name: name, symbol: "tag", query: ItemQuery().adding(.tag(name)), grouping: .kind, sort: .taskOrder)
    }
}

/// Saved views, kept per Mac (item-browser I3).
public enum SavedViews {
    public static let defaultsKey = "itemBrowser.savedViews"

    public static func load(_ defaults: UserDefaults = .standard) -> [ItemView] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([ItemView].self, from: data)) ?? []
    }

    public static func save(_ views: [ItemView], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(views) { defaults.set(data, forKey: defaultsKey) }
    }
}
