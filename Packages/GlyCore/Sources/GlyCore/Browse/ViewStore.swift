import Foundation
import GRDB

/// New saved view (createView), item-browser I3.
public struct ViewDraft: Codable, Equatable {
    public var name: String
    /// `ItemQuery` text form.
    public var query: String
    public var grouping: ItemGrouping
    public var sort: ItemSort
    public init(name: String, query: String, grouping: ItemGrouping = .none, sort: ItemSort = .changed) {
        self.name = name; self.query = query; self.grouping = grouping; self.sort = sort
    }
    public init(_ view: ItemView, name: String) {
        self.init(name: name, query: view.query.description, grouping: view.grouping, sort: view.sort)
    }
}

/// Partial view update (updateView). `nil` = unchanged.
public struct ViewPatch: Codable, Equatable {
    public var name: String?
    public var query: String?
    public var grouping: ItemGrouping?
    public var sort: ItemSort?
    public init(name: String? = nil, query: String? = nil, grouping: ItemGrouping? = nil, sort: ItemSort? = nil) {
        self.name = name; self.query = query; self.grouping = grouping; self.sort = sort
    }
    public init(_ view: ItemView) {
        self.init(name: view.name, query: view.query.description, grouping: view.grouping, sort: view.sort)
    }
}

public enum ViewQueries {
    /// Saved views in sidebar order.
    public static func list(_ db: Database) throws -> [ItemView] {
        try Row.fetchAll(db, sql: "SELECT * FROM live_views ORDER BY position, created_at").map(view)
    }

    public static func view(_ db: Database, id: String) throws -> ItemView? {
        try Row.fetchOne(db, sql: "SELECT * FROM live_views WHERE id = ?", arguments: [id]).map(view)
    }

    static func view(_ r: Row) -> ItemView {
        ItemView(id: r["id"], name: r["name"], symbol: r["symbol"], query: ItemQuery.parse(r["query"]),
                 grouping: ItemGrouping(rawValue: r["grouping"]) ?? .none, sort: ItemSort(rawValue: r["sort"]) ?? .changed)
    }
}

extension CommandHandler {
    func createView(_ draft: ViewDraft, batch: Batch) throws -> CommandOK {
        let name = try Self.viewName(draft.name)
        let position = (try Double.fetchOne(batch.db, sql: "SELECT MAX(position) FROM live_views") ?? 0) + 1
        let id = try batch.insert("views", ["name": name, "query": ItemQuery.parse(draft.query).description,
                                            "grouping": draft.grouping.rawValue, "sort": draft.sort.rawValue, "position": position])
        return CommandOK(id: id)
    }

    func updateView(_ id: String, _ patch: ViewPatch, batch: Batch) throws -> CommandOK {
        try Self.requireView(id, batch.db)
        var fields: Fields = [:]
        if let n = patch.name { fields["name"] = try Self.viewName(n) }
        if let q = patch.query { fields["query"] = ItemQuery.parse(q).description }
        if let g = patch.grouping { fields["grouping"] = g.rawValue }
        if let s = patch.sort { fields["sort"] = s.rawValue }
        return CommandOK(id: id, changed: !(try batch.update("views", id: id, fields)).isEmpty)
    }

    func deleteView(_ id: String, batch: Batch) throws -> CommandOK {
        try Self.requireView(id, batch.db)
        try batch.softDelete("views", id: id)
        return CommandOK(id: id)
    }

    static func requireView(_ id: String, _ db: Database) throws {
        if ItemView.presets.contains(where: { $0.id == id }) {
            throw CommandFailure(.validation, "“\(id)” is a preset view; preset views can't be changed.")
        }
        guard try ViewQueries.view(db, id: id) != nil else { throw CommandFailure(.notFound, "View \(id) not found.") }
    }

    static func viewName(_ raw: String) throws -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw CommandFailure(.validation, "A view needs a name.") }
        return n
    }
}
