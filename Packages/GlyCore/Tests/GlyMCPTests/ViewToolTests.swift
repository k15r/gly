import Foundation
import GRDB
import MCP
import XCTest
@testable import GlyCore
@testable import GlyMCP

/// specs/agent-access "Views over MCP", "Items over MCP" (item-browser I9).
final class ViewToolTests: XCTestCase {
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
    func array(_ v: Value?, _ k: String) -> [Value] { if case .array(let a)? = field(v, k) { return a } else { return [] } }
    func id(_ v: Value?) -> String { if case .string(let s)? = field(v, "id") { return s }; XCTFail("no id"); return "" }

    func testAgentSavesAView() async throws {
        let (v, isError, text) = await call("create_view", ["name": "Atlas this week", "query": "is:task #project/atlas due:week", "grouping": "due"])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(v, "name"), "Atlas this week")
        XCTAssertEqual(field(v, "query"), "is:task #project/atlas due:week")
        XCTAssertEqual(field(v, "grouping"), "due")
        XCTAssertEqual(field(v, "preset"), .bool(false))
        let (list, _, _) = await call("list_views", [:])
        XCTAssertEqual(array(list, "views").map { field($0, "name") }, ["All items", "Tasks", "Pages", "Bookmarks", "Meetings", "Atlas this week"])
        let writers = try await db.read { try String.fetchAll($0, sql: "SELECT DISTINCT writer FROM change_log WHERE table_name = 'views'") }
        XCTAssertEqual(writers, ["agent:claude-code@mac-test01"])
        let label = try await db.read { try $0.undoLabel(writer: "agent:claude-code@mac-test01") }
        XCTAssertEqual(label, "Save view “Atlas this week”")
    }

    func testAgentChangesAndDeletesAView() async throws {
        let (created, _, _) = await call("create_view", ["name": "Atlas", "query": "#project/atlas"])
        let viewID = id(created)
        let (updated, isError, text) = await call("update_view", ["id": .string(viewID), "query": "is:bookmark #project/atlas", "sort": "title"])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(field(updated, "query"), "is:bookmark #project/atlas")
        XCTAssertEqual(field(updated, "sort"), "title")
        XCTAssertEqual(field(updated, "name"), "Atlas", "unchanged fields stay")
        let (_, deleteError, _) = await call("delete_view", ["id": .string(viewID)])
        XCTAssertFalse(deleteError)
        let (list, _, _) = await call("list_views", [:])
        XCTAssertEqual(array(list, "views").count, 5)
    }

    func testPresetViewsAreReadOnly() async {
        let (_, updateError, text) = await call("update_view", ["id": "tasks", "name": "Mine"])
        XCTAssertTrue(updateError)
        XCTAssertTrue(text.contains("preset"), text)
        let (_, deleteError, _) = await call("delete_view", ["id": "tasks"])
        XCTAssertTrue(deleteError)
        let (_, badSort, _) = await call("create_view", ["name": "X", "sort": "sideways"])
        XCTAssertTrue(badSort)
    }

    func testAgentRunsAView() async throws {
        _ = await call("create_task", ["title": "Later", "tags": ["project/atlas"], "due_date": "2099-01-02"])
        _ = await call("create_task", ["title": "Sooner", "tags": ["project/atlas"], "due_date": "2099-01-01"])
        _ = await call("create_task", ["title": "Elsewhere", "tags": ["project/beta"]])
        let (created, _, _) = await call("create_view", ["name": "Atlas by due", "query": "is:task #project/atlas", "sort": "due"])
        let (v, isError, text) = await call("list_items", ["view": .string(id(created))])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(array(v, "items").map { field($0, "title") }, ["Sooner", "Later"], "the view's filter and order")
        XCTAssertEqual(array(v, "items").first.flatMap { field($0, "kind") }, "task")
        XCTAssertEqual(array(v, "items").first.flatMap { field($0, "status") }, "open", "task fields come along")
        let (narrowed, _, _) = await call("list_items", ["view": .string(id(created)), "query": "later"])
        XCTAssertEqual(array(narrowed, "items").map { field($0, "title") }, ["Later"])
        let (preset, _, _) = await call("list_items", ["view": "tasks"])
        XCTAssertEqual(array(preset, "items").count, 3)
    }

    func testAgentFiltersDirectly() async throws {
        _ = await call("create_bookmark", ["url": "https://example.com/ops", "title": "Ops board", "tags": ["ops/infra"]])
        _ = await call("create_bookmark", ["url": "https://example.com/wiki", "title": "Wiki", "tags": ["team"]])
        _ = await call("create_page", ["title": "Ops notes", "tags": ["ops"]])
        let (v, isError, text) = await call("list_items", ["query": "is:bookmark #ops"])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(array(v, "items").map { field($0, "title") }, ["Ops board"])
        XCTAssertEqual(array(v, "items").first.flatMap { field($0, "url") }, "https://example.com/ops")
        let (limited, _, _) = await call("list_items", ["query": "", "limit": 1])
        XCTAssertEqual(array(limited, "items").count, 1)
        XCTAssertEqual(field(limited, "has_more"), .bool(true))
        let (_, missing, _) = await call("list_items", ["view": "nope"])
        XCTAssertTrue(missing)
    }
}
