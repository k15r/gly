import Foundation

/// Access policy of the local HTTP endpoint (design M6): token in the path or as Bearer, Origin allow list,
/// CORS only for allowed origins.
public struct HTTPGate {
    public let token: String
    /// Exact origins (scheme://host[:port]) allowed to call from a browser.
    public let allowedOrigins: Set<String>

    public init(token: String, allowedOrigins: [String]) {
        self.token = token
        self.allowedOrigins = Set(allowedOrigins.map(Self.normalize).filter { !$0.isEmpty })
    }

    public enum Decision: Equatable {
        /// Pass to MCP; add these headers (CORS) to the response.
        case allow(responseHeaders: [String: String])
        /// Answer directly (rejections and CORS preflight), without revealing data.
        case respond(status: Int, headers: [String: String])
    }

    public func decide(_ request: WireRequest) -> Decision {
        // Origin first: a browser page that isn't allowed learns nothing, not even whether the token is right.
        var cors: [String: String] = [:]
        if let origin = request.headers["origin"] {
            guard allowedOrigins.contains(Self.normalize(origin)) else { return .respond(status: 403, headers: [:]) }
            cors = ["Access-Control-Allow-Origin": origin, "Vary": "Origin"]
        }
        guard let suffix = Self.mcpPathSuffix(request.path) else { return .respond(status: 404, headers: cors) }
        if request.method == "OPTIONS" {
            guard !cors.isEmpty else { return .respond(status: 405, headers: [:]) }
            return .respond(status: 204, headers: cors.merging([
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Accept, Authorization, Mcp-Protocol-Version",
                "Access-Control-Max-Age": "600",
            ]) { a, _ in a })
        }
        let presented = suffix.isEmpty ? Self.bearer(request.headers["authorization"]) : suffix
        guard let presented, Self.constantTimeEqual(presented, token) else { return .respond(status: 401, headers: cors) }
        guard request.method == "POST" else { return .respond(status: 405, headers: cors.merging(["Allow": "POST"]) { a, _ in a }) }
        return .allow(responseHeaders: cors)
    }

    /// `/mcp` → "", `/mcp/<token>` → "<token>", anything else → nil.
    static func mcpPathSuffix(_ path: String) -> String? {
        if path == "/mcp" || path == "/mcp/" { return "" }
        guard path.hasPrefix("/mcp/") else { return nil }
        let rest = path.dropFirst("/mcp/".count)
        return rest.contains("/") ? nil : String(rest)
    }

    static func bearer(_ header: String?) -> String? {
        guard let header, header.lowercased().hasPrefix("bearer ") else { return nil }
        return String(header.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ origin: String) -> String {
        var o = origin.trimmingCharacters(in: .whitespaces).lowercased()
        while o.hasSuffix("/") { o.removeLast() }
        return o
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) { diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0) }
        return diff == 0
    }
}
