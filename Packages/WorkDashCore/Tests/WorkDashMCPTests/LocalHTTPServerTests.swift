import Foundation
import GRDB
import MCP
import Network
import XCTest
@testable import WorkDashCore
@testable import WorkDashMCP

/// The listener end to end on loopback with a real MCP server behind it (task 5.3, 5.4).
final class LocalHTTPServerTests: XCTestCase {
    var db: DatabaseQueue!
    var http: LocalHTTPServer!
    var port: UInt16 = 0

    override func setUp() async throws {
        db = try StoreFactory.openInMemory()
        let tools = WorkDashTools(writer: db, calendar: FakeEventSource(), hiddenCalendarIDs: { [] }, deviceID: "mac-test01")
        let mcp = try await WorkDashMCPServer(tools: tools)
        http = LocalHTTPServer(port: 0, gate: HTTPGate(token: "tok", allowedOrigins: [])) { await mcp.handle($0) }
        try await http.start()
        port = http.port!
    }
    override func tearDown() { http.stop() }

    func post(_ path: String, _ body: String, headers: [String: String] = [:]) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    func testValidRequestListsTools() async throws {
        let (status, body) = try await post("/mcp/tok", #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(body.contains("get_schedule"))
    }

    func testWrongTokenGets401WithoutData() async throws {
        let (status, body) = try await post("/mcp/nope", #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        XCTAssertEqual(status, 401)
        XCTAssertFalse(body.contains("get_schedule"))
    }

    func testBlockedOrigin() async throws {
        let (status, _) = try await post("/mcp/tok", #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#, headers: ["Origin": "https://evil.example"])
        XCTAssertEqual(status, 403)
    }

    func testHTTPWriterFromUserAgent() async throws {
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"From Joule"}}}"#
        let (status, _) = try await post("/mcp/tok", call, headers: ["User-Agent": "joule/1.0"])
        XCTAssertEqual(status, 200)
        let writer = try await db.read { try String.fetchOne($0, sql: "SELECT modified_by FROM items") }
        XCTAssertEqual(writer, "agent:joule@mac-test01")
    }

    func testOnlyLoopbackIsBound() async throws {
        // The listener's local endpoint is 127.0.0.1, so other interfaces (and other machines) can't connect.
        let c = NWConnection(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let refused = await withCheckedContinuation { (k: CheckedContinuation<Bool, Never>) in
            var done = false
            c.stateUpdateHandler = { s in
                switch s {
                case .ready: if !done { done = true; k.resume(returning: false) }
                case .failed, .waiting: if !done { done = true; k.resume(returning: true) }
                default: break
                }
            }
            c.start(queue: .global())
        }
        c.cancel()
        XCTAssertTrue(refused, "::1 must not reach a listener bound to 127.0.0.1")
    }

    func testRedaction() {
        XCTAssertEqual(LocalHTTPServer.redact("/mcp/secret"), "/mcp/<token>")
        XCTAssertEqual(LocalHTTPServer.redact("/other"), "/other")
    }
}
