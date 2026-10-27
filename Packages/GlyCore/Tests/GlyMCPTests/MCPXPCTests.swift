import Foundation
import GRDB
import XCTest
@testable import GlyCore
@testable import GlyMCP

/// MCP messages through the real XPC encoding (anonymous listener), as `gly-mcp` sends them (task 4.1).
final class MCPXPCTests: XCTestCase {
    func testToolCallOverXPCIsAttributedToTheClient() async throws {
        let db = try StoreFactory.openInMemory()
        let tools = GlyTools(writer: db, calendar: FakeEventSource(), hiddenCalendarIDs: { [] }, deviceID: "mac-test01")
        let server = try await GlyMCPServer(tools: tools)
        let delegate = AgentListenerDelegate(service: AgentService(writer: db, mcp: { await server.handleStdio($0, client: $1) }),
                                             codeRequirement: nil)
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }

        let client = AgentClient(endpoint: listener.endpoint)
        let message = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"Via gly-mcp"}}}"#
        guard case .success(let reply?) = await client.mcp(Data(message.utf8), client: "test") else { return XCTFail("no reply") }
        let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any]
        XCTAssertEqual(object?["id"] as? Int, 7)
        let writer = try await db.read { try String.fetchOne($0, sql: "SELECT modified_by FROM items") }
        XCTAssertEqual(writer, "agent:test@mac-test01")

        guard case .success(let none) = await client.mcp(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), client: "test") else { return XCTFail() }
        XCTAssertNil(none, "notifications get no reply")
    }
}
