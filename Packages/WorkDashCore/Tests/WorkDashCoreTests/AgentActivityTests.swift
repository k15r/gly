import GRDB
import XCTest
@testable import WorkDashCore

final class AgentActivityTests: XCTestCase {
    func testRecentAgentChangesNewestFirstWithoutUserChanges() throws {
        let db = try StoreFactory.openInMemory()
        let h = CommandHandler(writer: db)
        _ = h.perform(.createTask(TaskDraft(title: "Mine")), writer: "user@mac")
        guard case .ok(let a) = h.perform(.createTask(TaskDraft(title: "From agent")), writer: "agent:claude-code@mac") else { return XCTFail() }
        _ = h.perform(.setStatus(id: a.id!, .done), writer: "agent:claude-code@mac")
        let changes = try db.read { try AgentActivity.recent($0) }
        XCTAssertEqual(changes.map(\.label), ["Complete “From agent”", "Create “From agent”"])
        XCTAssertEqual(Set(changes.map(\.writer)), ["agent:claude-code@mac"])
        XCTAssertEqual(try db.read { try AgentActivity.recent($0, limit: 1) }.count, 1)
    }
}
