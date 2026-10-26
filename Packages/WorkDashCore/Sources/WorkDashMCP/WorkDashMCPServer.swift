import Foundation
import MCP

/// The MCP server of the agent (design M2): one SDK `Server` on a stateless transport, fed single
/// JSON-RPC messages from stdio (via XPC) and HTTP alike.
public final class WorkDashMCPServer: @unchecked Sendable {
    /// Header carrying the MCP client name for messages that arrive via `wd-mcp` (design M4).
    public static let clientHeader = "x-workdash-client"

    let tools: WorkDashTools
    let server: Server
    let transport: StatelessHTTPServerTransport

    /// Transport-level checks (token, Origin) are done before a request reaches this type (design M6).
    struct AcceptAll: HTTPRequestValidationPipeline {
        func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? { nil }
    }

    public init(tools: WorkDashTools, version: String = "1.0") async throws {
        self.tools = tools
        server = Server(name: "workdash", version: version,
                        instructions: "WorkDash is the user's single source for their day: calendar appointments (read-only) and tasks. Read the schedule with get_schedule, find tasks with list_tasks, and keep tasks up to date with create_task, update_task and delete_task. Reuse existing tags (list_tags).",
                        capabilities: .init(tools: .init(listChanged: false)))
        transport = StatelessHTTPServerTransport(validationPipeline: AcceptAll())
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: ToolDefinitions.all) }
        await server.withMethodHandler(CallTool.self) { [tools] params in
            await tools.call(params.name, arguments: params.arguments, client: Self.client(from: Server.currentHandlerContext?.httpContext))
        }
        try await server.start(transport: transport)
    }

    /// Client name for attribution: the `wd-mcp` header, else the first User-Agent product token, else "http".
    static func client(from request: HTTPRequest?) -> String? {
        guard let headers = request?.headers else { return nil }
        func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name }?.value }
        if let c = header(clientHeader), !c.isEmpty { return c }
        if let ua = header("user-agent"), let token = ua.split(whereSeparator: { $0 == "/" || $0 == " " }).first { return String(token) }
        return "http"
    }

    /// Handles one HTTP request that already passed the token/Origin checks.
    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.method.uppercased() == "POST", let body = request.body else { return await transport.handleRequest(request) }
        // Unique ids so concurrent clients reusing the same id don't collide in the transport (design M2).
        let (rewritten, original) = Self.rewriteID(body)
        let response = await transport.handleRequest(HTTPRequest(method: request.method, headers: request.headers, body: rewritten, path: request.path))
        guard let original, case .data(let data, let headers) = response else { return response }
        return .data(Self.restoreID(data, original), headers: headers)
    }

    /// Handles one JSON-RPC message from `wd-mcp`. Returns the reply, or nil for notifications.
    public func handleStdio(_ message: Data, client: String?) async -> Data? {
        var headers = ["content-type": "application/json", "accept": "application/json"]
        if let client { headers[Self.clientHeader] = client }
        let response = await handle(HTTPRequest(method: "POST", headers: headers, body: message))
        switch response {
        case .data(let data, _): return data
        case .accepted, .ok: return nil
        default: return response.bodyData
        }
    }

    // MARK: - Request id rewriting

    static func rewriteID(_ body: Data) -> (Data, Any?) {
        guard var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              object["method"] != nil, let id = object["id"] else { return (body, nil) }
        object["id"] = "wd-" + UUID().uuidString
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return (body, nil) }
        return (data, id)
    }

    static func restoreID(_ body: Data, _ id: Any) -> Data {
        guard var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return body }
        object["id"] = id
        return (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? body
    }
}
