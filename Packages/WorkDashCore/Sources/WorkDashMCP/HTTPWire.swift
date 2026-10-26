import Foundation

/// A parsed HTTP/1.1 request (minimal: what the local MCP endpoint needs, design M6).
public struct WireRequest: Equatable {
    public let method: String
    /// Request target as sent, e.g. `/mcp/<token>`.
    public let target: String
    /// Header names lowercased.
    public let headers: [String: String]
    public let body: Data

    public var path: String { String(target.split(separator: "?", maxSplits: 1).first ?? "") }
}

/// Incremental parser for one request per connection (`Connection: close` after the response).
public struct HTTPRequestParser {
    public enum Outcome: Equatable {
        case incomplete
        case request(WireRequest)
        /// Reject with this status (400, 411, 413, 431).
        case error(Int)
    }

    public static let maxBody = 1 << 20          // 1 MB
    public static let maxHead = 16 << 10         // 16 KB

    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> Outcome {
        buffer.append(data)
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > Self.maxHead ? .error(431) : .incomplete
        }
        guard headEnd.lowerBound <= Self.maxHead,
              let head = String(data: buffer[buffer.startIndex..<headEnd.lowerBound], encoding: .utf8) else { return .error(431) }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."), !requestLine[0].isEmpty,
              requestLine[1].hasPrefix("/") else { return .error(400) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .error(400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, !name.contains(" ") else { return .error(400) }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .error(411) }   // chunked bodies aren't supported
        let method = String(requestLine[0]).uppercased()
        var length = 0
        if let raw = headers["content-length"] {
            guard let n = Int(raw), n >= 0 else { return .error(400) }
            length = n
        } else if method == "POST" {
            return .error(411)
        }
        guard length <= Self.maxBody else { return .error(413) }
        let bodyStart = headEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + length)]
        return .request(WireRequest(method: method, target: String(requestLine[1]), headers: headers, body: Data(body)))
    }
}

/// Serializes HTTP/1.1 responses.
public enum HTTPResponseWriter {
    static let reasons = [200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
                          403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 411: "Length Required",
                          413: "Payload Too Large", 431: "Request Header Fields Too Large", 500: "Internal Server Error"]

    public static func data(status: Int, headers: [String: String] = [:], body: Data = Data()) -> Data {
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        if !body.isEmpty && all.keys.first(where: { $0.lowercased() == "content-type" }) == nil { all["Content-Type"] = "application/json" }
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "Status")\r\n"
        for (k, v) in all.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
