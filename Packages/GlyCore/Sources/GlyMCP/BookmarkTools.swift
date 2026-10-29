import Foundation
import MCP
import GlyCore

/// Bookmarks over MCP (specs/agent-access "Bookmarks over MCP", bookmarks B7).
extension GlyTools {
    func bookmark(_ id: String) throws -> BookmarkItem {
        guard let b = try reader.read({ try BookmarkQueries.bookmark($0, id: id) }) else { throw try notFound("Bookmark", id) }
        return b
    }

    static func bookmarkValue(_ b: BookmarkItem) -> Value {
        .object([
            "id": .string(b.id), "title": .string(b.title), "url": .string(b.url), "description": .string(b.description),
            "tags": .array(b.tags.map { .string($0) }),
            "created_at": .string(timestamp.string(from: b.createdAt)),
            "modified_at": .string(timestamp.string(from: b.modifiedAt)),
            "modified_by": .string(b.modifiedBy),
        ])
    }

    /// Without a title the host is used (agents can't fetch the page). A known URL returns its bookmark, `existing: true`.
    func createBookmark(_ args: Arguments, writer: String) throws -> Value {
        let draft = BookmarkDraft(url: try args.requiredString("url"), title: try args.string("title") ?? "",
                                  description: try args.string("description") ?? "", tags: try args.strings("tags") ?? [])
        let ok = try performOK(.createBookmark(draft), writer: writer)
        guard case .object(var o) = Self.bookmarkValue(try bookmark(ok.id ?? "")) else { return .null }
        o["existing"] = .bool(!ok.changed)
        return .object(o)
    }

    func updateBookmark(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        _ = try bookmark(id)
        let patch = BookmarkPatch(title: try args.string("title"), url: try args.string("url"),
                                  description: try args.string("description"), tags: try args.strings("tags"))
        try perform(.updateBookmark(id: id, patch), writer: writer)
        return Self.bookmarkValue(try bookmark(id))
    }

    func listBookmarks(_ args: Arguments) throws -> Value {
        let tag = try args.string("tag").map(TagName.init)
        let text = try args.string("text")
        let limit = min(200, max(1, try args.int("limit") ?? 50))
        let found = try reader.read { try BookmarkQueries.list($0, tag: tag, text: text, limit: limit) }
        return .object(["bookmarks": .array(found.map(Self.bookmarkValue))])
    }

    func deleteBookmark(_ args: Arguments, writer: String) throws -> Value {
        let id = try args.requiredString("id")
        _ = try bookmark(id)
        try perform(.deleteBookmark(id: id), writer: writer)
        return .object(["deleted": .string(id)])
    }
}

extension ToolDefinitions {
    static let bookmarkShape = "A bookmark is {id, title, url, description, tags, created_at, modified_at, modified_by}."

    // swiftlint:disable line_length
    static let bookmarkTools: [Tool] = [
        Tool(name: "create_bookmark",
             description: "Save a web link (http, https or mailto) as a bookmark, with a title, an optional description (markdown) and tags. Without a title the host is used, so pass the page's title when you know it. A URL that is already bookmarked is not saved twice: the existing bookmark comes back with existing: true. \(bookmarkShape)",
             inputSchema: object([
                "url": string("The link, e.g. https://example.com/docs."),
                "title": string("Title, e.g. the page's title."),
                "description": string("What the link is for (markdown)."),
                "tags": tagsSchema,
             ], required: ["url"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "update_bookmark",
             description: "Change a bookmark. Only given fields change; one step in the history. tags replaces the tag set. A url that another bookmark has is refused. \(bookmarkShape)",
             inputSchema: object([
                "id": string("Bookmark id."),
                "title": string("New title."),
                "url": string("New link."),
                "description": string("New description (markdown)."),
                "tags": tagsSchema,
             ], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
        Tool(name: "list_bookmarks",
             description: "Bookmarks by title, optionally only those with a tag (or a tag below it) and those whose title, URL, description or tags contain every word of text. Returns {bookmarks: [...]}. \(bookmarkShape)",
             inputSchema: object([
                "tag": string("Tag name, e.g. \"project/atlas\"."),
                "text": string("Words to look for."),
                "limit": .object(["type": "integer", "minimum": 1, "maximum": 200, "description": "Maximum number of bookmarks (default 50)."]),
             ]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "delete_bookmark",
             description: "Delete a bookmark. It goes to the trash, from which restore brings it back.",
             inputSchema: object(["id": string("Bookmark id.")], required: ["id"]),
             annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false)),
    ]
    // swiftlint:enable line_length
}
