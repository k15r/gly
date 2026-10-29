import Foundation
import GRDB
import MCP
import XCTest
@testable import GlyCore
@testable import GlyMCP

/// specs/agent-access "Bookmarks over MCP" (bookmarks B7).
final class BookmarkToolTests: XCTestCase {
    var db: DatabaseQueue!
    var tools: GlyTools!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        tools = GlyTools(writer: db, calendar: FakeEventSource(), hiddenCalendarIDs: { [] }, deviceID: "mac-test01")
    }

    func call(_ name: String, _ args: [String: Value]) async -> (Value?, Bool, String) {
        let r = await tools.call(name, arguments: args, client: "claude-code")
        var text = ""; if case .text(let t, _, _)? = r.content.first { text = t }
        return (r.structuredContent, r.isError ?? false, text)
    }
    func field(_ v: Value?, _ k: String) -> Value? { if case .object(let o)? = v { return o[k] } else { return nil } }
    func bookmarks(_ v: Value?) -> [Value] { if case .array(let a)? = field(v, "bookmarks") { return a } else { return [] } }

    func testAgentSavesALink() async throws {
        let (v, isError, text) = await call("create_bookmark", ["url": "https://wiki.example/runbook", "title": "Runbook",
                                                                 "description": "on-call steps", "tags": ["project/atlas"]])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(v, "title"), "Runbook")
        XCTAssertEqual(field(v, "url"), "https://wiki.example/runbook")
        XCTAssertEqual(field(v, "tags"), .array(["project/atlas"]))
        XCTAssertEqual(field(v, "existing"), .bool(false))
        XCTAssertEqual(field(v, "modified_by"), "agent:claude-code@mac-test01")
        // In the Bookmarks list and on the tag page's bookmarks.
        let listed = try await db.read { try BookmarkQueries.list($0, tag: TagName("project/atlas")).map(\.title) }
        XCTAssertEqual(listed, ["Runbook"])
        let writers = try await db.read { try String.fetchAll($0, sql: "SELECT DISTINCT writer FROM change_log") }
        XCTAssertEqual(writers, ["agent:claude-code@mac-test01"])
        let batches = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(DISTINCT batch) FROM change_log") }
        XCTAssertEqual(batches, 1, "one step")
    }

    func testExistingURLReturnsTheBookmark() async throws {
        let (first, _, _) = await call("create_bookmark", ["url": "https://wiki.example/runbook", "title": "Runbook"])
        let (again, isError, _) = await call("create_bookmark", ["url": "HTTPS://WIKI.example/runbook"])
        XCTAssertFalse(isError)
        XCTAssertEqual(field(again, "id"), field(first, "id"))
        XCTAssertEqual(field(again, "existing"), .bool(true))
        let count = try await db.read { try BookmarkQueries.count($0) }
        XCTAssertEqual(count, 1)
    }

    func testTitleDefaultsToTheHost() async throws {
        let (v, _, _) = await call("create_bookmark", ["url": "https://docs.example/a/b"])
        XCTAssertEqual(field(v, "title"), "docs.example")
    }

    func testAgentFindsALink() async throws {
        _ = await call("create_bookmark", ["url": "https://wiki.example/runbook", "title": "Runbook"])
        _ = await call("create_bookmark", ["url": "https://grafana.example/d/1", "title": "Latency", "description": "see the runbook first"])
        _ = await call("create_bookmark", ["url": "https://food.example", "title": "Recipes", "tags": ["home"]])
        let (v, isError, text) = await call("list_bookmarks", ["text": "runbook"])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(bookmarks(v).map { field($0, "title") }, ["Latency", "Runbook"], "title, URL or description")
        XCTAssertEqual(bookmarks(v).first.flatMap { field($0, "description") }, "see the runbook first")
        let (byTag, _, _) = await call("list_bookmarks", ["tag": "home"])
        XCTAssertEqual(bookmarks(byTag).map { field($0, "title") }, ["Recipes"])
        let (all, _, _) = await call("list_bookmarks", [:])
        XCTAssertEqual(bookmarks(all).count, 3)
    }

    func testUpdateDeleteAndRestore() async throws {
        let (created, _, _) = await call("create_bookmark", ["url": "https://wiki.example/runbook", "title": "Runbook"])
        guard case .string(let id)? = field(created, "id") else { return XCTFail("no id") }
        let (updated, isError, text) = await call("update_bookmark", ["id": .string(id), "description": "steps", "tags": ["ops"]])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(updated, "description"), "steps")
        XCTAssertEqual(field(updated, "tags"), .array(["ops"]))
        _ = await call("create_bookmark", ["url": "https://other.example", "title": "Other"])
        let (_, conflict, _) = await call("update_bookmark", ["id": .string(id), "url": "https://other.example"])
        XCTAssertTrue(conflict, "a URL another bookmark has is refused")

        let (_, deleteError, _) = await call("delete_bookmark", ["id": .string(id)])
        XCTAssertFalse(deleteError)
        let (trash, _, _) = await call("list_trash", [:])
        if case .array(let items)? = field(trash, "items") {
            XCTAssertEqual(items.map { field($0, "kind") }, ["bookmark"])
        } else { XCTFail("no trash items") }
        let (restored, restoreError, restoreText) = await call("restore", ["id": .string(id)])
        XCTAssertFalse(restoreError, restoreText)
        XCTAssertEqual(field(restored, "url"), "https://wiki.example/runbook")
        let (_, missing, _) = await call("delete_bookmark", ["id": "nope"])
        XCTAssertTrue(missing)
    }

    func testToolsAreListed() {
        let names = Set(ToolDefinitions.all.map(\.name))
        for n in ["create_bookmark", "update_bookmark", "list_bookmarks", "delete_bookmark"] { XCTAssertTrue(names.contains(n), n) }
    }
}
