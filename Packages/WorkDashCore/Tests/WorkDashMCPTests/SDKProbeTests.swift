import Foundation
import MCP
import XCTest

/// Task 1.1 probe: the SDK's Server + StatelessHTTPServerTransport handle single JSON-RPC messages
/// without an HTTP framework. Kept as a regression test for the SDK path (design M2).
final class SDKProbeTests: XCTestCase {
    struct AllowAll: HTTPRequestValidationPipeline {
        func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? { nil }
    }

    func post(_ t: StatelessHTTPServerTransport, _ json: String) async -> HTTPResponse {
        await t.handleRequest(HTTPRequest(method: "POST",
                                          headers: ["Content-Type": "application/json", "Accept": "application/json"],
                                          body: Data(json.utf8)))
    }

    func testInitializeAndToolsListThroughStatelessTransport() async throws {
        let server = Server(name: "probe", version: "0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(name: "get_schedule", description: "d", inputSchema: .object(["type": "object"]))])
        }
        let transport = StatelessHTTPServerTransport(validationPipeline: AllowAll())
        try await server.start(transport: transport)

        let initResponse = await post(transport, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe-client","version":"1"}}}"#)
        XCTAssertEqual(initResponse.statusCode, 200)
        XCTAssertTrue(String(decoding: initResponse.bodyData ?? Data(), as: UTF8.self).contains("serverInfo"))

        // A later request on its own (stateless): no session needed.
        let list = await post(transport, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        XCTAssertEqual(list.statusCode, 200)
        XCTAssertTrue(String(decoding: list.bodyData ?? Data(), as: UTF8.self).contains("get_schedule"))

        let note = await post(transport, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertEqual(note.statusCode, 202)
        await server.stop()
    }
}
