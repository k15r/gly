import Foundation
import MCP
import GlyCore

/// Views and items over MCP (specs/agent-access "Views over MCP", "Items over MCP", item-browser I9).
extension GlyTools {
    static func viewValue(_ v: ItemView) -> Value {
        .object(["id": .string(v.id), "name": .string(v.name), "query": .string(v.query.description),
                 "grouping": .string(v.grouping.rawValue), "sort": .string(v.sort.rawValue), "preset": .bool(v.isPreset)])
    }

    func view(_ id: String) throws -> ItemView {
        if let preset = ItemView.presets.first(where: { $0.id == id }) { return preset }
        guard let v = try reader.read({ try ViewQueries.view($0, id: id) }) else { throw ToolError("View \(id) not found (list_views shows the views).") }
        return v
    }

    func listViews(_ args: Arguments) throws -> Value {
        let saved = try reader.read { try ViewQueries.list($0) }
        return .object(["views": .array((ItemView.presets + saved).map(Self.viewValue))])
    }

    func createView(_ args: Arguments, writer: String) throws -> Value {
        let draft = ViewDraft(name: try args.requiredString("name"), query: try args.string("query") ?? "",
                              grouping: try grouping(args) ?? .none, sort: try sort(args) ?? .changed)
        return Self.viewValue(try view(try perform(.createView(draft), writer: writer)))
    }

    func updateView(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        let patch = ViewPatch(name: try args.string("name"), query: try args.string("query"), grouping: try grouping(args), sort: try sort(args))
        try perform(.updateView(id: id, patch), writer: writer)
        return Self.viewValue(try view(id))
    }

    func deleteView(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        try perform(.deleteView(id: id), writer: writer)
        return .object(["deleted": .string(id)])
    }

    /// Items of a view (its filter and order) or of a filter; `query` together with `view` narrows the view.
    func listItems(_ args: Arguments) throws -> Value {
        let base = try args.string("view").map(view)
        var query = base?.query ?? ItemQuery()
        if let typed = try args.string("query") {
            let extra = ItemQuery.parse(typed)
            extra.tokens.forEach { query.add($0) }
            query.text = [query.text, extra.text].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let order = try sort(args) ?? base?.sort ?? (query.text.isEmpty ? .changed : .relevance)
        let limit = min(500, max(1, try args.int("limit") ?? 50))
        let items = try reader.read { try BrowseQueries.items($0, query, sort: order, now: now(), limit: limit + 1) }
        return .object(["query": .string(query.description), "sort": .string(order.rawValue),
                        "items": .array(items.prefix(limit).map(itemValue)), "has_more": .bool(items.count > limit)])
    }

    func itemValue(_ item: BrowseItem) -> Value {
        var o: [String: Value] = [:]
        if let task = item.task, case .object(let t) = encode(task) { o = t }
        o["id"] = .string(item.id); o["kind"] = .string(item.kind.rawValue); o["title"] = .string(item.title)
        o["tags"] = .array(item.tags.map { .string($0) })
        o["excerpt"] = .string(item.excerpt)
        o["modified_at"] = .string(Self.timestamp.string(from: item.modifiedAt))
        o["modified_by"] = .string(item.modifiedBy)
        if let url = item.url { o["url"] = .string(url) }
        return .object(o)
    }

    private func grouping(_ args: Arguments) throws -> ItemGrouping? {
        guard let g = try args.string("grouping") else { return nil }
        guard let value = ItemGrouping(rawValue: g) else { throw ToolError("Unknown grouping “\(g)” (none, kind, due, status, tag).") }
        return value
    }

    private func sort(_ args: Arguments) throws -> ItemSort? {
        guard let s = try args.string("sort") else { return nil }
        guard let value = ItemSort(rawValue: s) else {
            throw ToolError("Unknown sort “\(s)” (\(ItemSort.allCases.map(\.rawValue).joined(separator: ", "))).")
        }
        return value
    }
}

extension ToolDefinitions {
    // swiftlint:disable line_length
    static let querySyntax = "Filters use the item browser's syntax: is:task|page|bookmark|meeting, #tag (that tag or below; several must all match), -#tag (exclude), untagged, status:open|snoozed|done|dropped (tasks), due:overdue|today|week|none, prio:<none|low|normal|high|urgent>, effort:<XS..XL>, changed:today|7d|30d, by:me|agent, host:<domain> (bookmarks); other words search titles and texts. Example: \"is:task #project/atlas due:week review\"."
    static let viewShape = "A view is {id, name, query, grouping (none|kind|due|status|tag), sort (relevance|changed|due|title|taskOrder), preset}."
    static let groupingSchema = string("How gly groups the view's items.", enum: ItemGrouping.allCases.map { .string($0.rawValue) })
    static let sortSchema = string("Order of the items.", enum: ItemSort.allCases.map { .string($0.rawValue) })

    static let viewTools: [Tool] = [
        Tool(name: "list_views",
             description: "The views in gly's sidebar: the presets (All items, Tasks, Pages, Bookmarks, Meetings; preset: true, read-only) and the saved views. \(viewShape) Run one with list_items {view: id}.",
             inputSchema: object([:]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "create_view",
             description: "Save a view: a named filter that appears under Saved Views in gly's sidebar. One step in the history (undoable in gly). \(querySyntax) \(viewShape)",
             inputSchema: object([
                "name": string("Name shown in the sidebar."),
                "query": string("The filter."),
                "grouping": groupingSchema,
                "sort": sortSchema,
             ], required: ["name"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)),
        Tool(name: "update_view",
             description: "Change a saved view (not a preset). Only given fields change; one step in the history. \(querySyntax) \(viewShape)",
             inputSchema: object([
                "id": string("View id (from list_views)."),
                "name": string("New name."),
                "query": string("New filter (replaces the old one)."),
                "grouping": groupingSchema,
                "sort": sortSchema,
             ], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "delete_view",
             description: "Delete a saved view (not a preset). Undoable in gly.",
             inputSchema: object(["id": string("View id (from list_views).")], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)),
        Tool(name: "list_items",
             description: "Items (tasks, pages, bookmarks, meeting notes) matching a filter, or the items of a view (its filter and order; a query then narrows it further). Returns {query, sort, items: [{id, kind, title, tags, excerpt, modified_at, modified_by, url (bookmarks), task fields (tasks)}], has_more}. \(querySyntax)",
             inputSchema: object([
                "query": string("The filter."),
                "view": string("A view id from list_views."),
                "sort": sortSchema,
                "limit": .object(["type": "integer", "minimum": 1, "maximum": 500, "description": "Maximum number of items (default 50)."]),
             ]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
    ]
    // swiftlint:enable line_length
}
