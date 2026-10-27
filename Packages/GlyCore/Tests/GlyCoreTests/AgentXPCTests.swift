import Foundation
import GRDB
import XCTest
@testable import GlyCore

/// Exercises the real XPC encoding through an anonymous listener (no launchd, no signing).
final class AgentXPCTests: XCTestCase {
    var listener: NSXPCListener!
    var delegate: AgentListenerDelegate!
    var db: DatabaseQueue!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        delegate = AgentListenerDelegate(service: AgentService(writer: db), codeRequirement: nil)
        listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
    }
    override func tearDown() { listener.invalidate() }

    func testPingCreateAndUndoRoundTrip() async throws {
        let client = AgentClient(endpoint: listener.endpoint)
        let ping = await client.perform(.ping, writer: "user@mac")
        XCTAssertEqual(ping, .ok(CommandOK(changed: false, message: "pong")))

        guard case .ok(let created) = await client.perform(.createTask(TaskDraft(title: "Via XPC", tags: ["person/alex"])), writer: "user@mac"),
              let id = created.id else { return XCTFail("create failed") }
        let row = try await db.read { try Row.fetchOne($0, sql: "SELECT title, modified_by FROM live_items WHERE id = ?", arguments: [id]) }
        XCTAssertEqual(row?["title"] as String?, "Via XPC")
        XCTAssertEqual(row?["modified_by"] as String?, "user@mac", "writer passed through")

        let undo = await client.perform(.undo, writer: "user@mac")
        XCTAssertTrue(undo.isOK)
        let alive = try await db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM live_items") }
        XCTAssertEqual(alive, 0)
    }

    func testValidationErrorTravelsBack() async {
        let client = AgentClient(endpoint: listener.endpoint)
        let r = await client.perform(.createTask(TaskDraft(title: "")), writer: "user@mac")
        XCTAssertEqual(r, .failure(CommandFailure(.validation, "A task needs a title.")))
    }

    func testUnreachableAgentGivesUnavailableError() async {
        listener.invalidate()
        let client = AgentClient(endpoint: listener.endpoint, timeout: 2)
        let r = await client.perform(.ping, writer: "user@mac")
        guard case .failure(let f) = r else { return XCTFail("expected failure") }
        XCTAssertEqual(f.code, .unavailable)
    }
}
