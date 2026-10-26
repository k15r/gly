import Foundation
import MCP
import Network

/// The local MCP endpoint (design M6): loopback only, one request per connection, gate before MCP.
public final class LocalHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let requestedPort: UInt16
    private let gate: HTTPGate
    private let handler: Handler
    private let log: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "dev.k15r.workdash.http")
    private var listener: NWListener?

    public init(port: UInt16, gate: HTTPGate, log: @escaping @Sendable (String) -> Void = { _ in }, handler: @escaping Handler) {
        self.requestedPort = port
        self.gate = gate
        self.handler = handler
        self.log = log
    }

    /// The bound port once started (useful with port 0 in tests).
    public private(set) var port: UInt16?

    /// Starts listening on 127.0.0.1 and returns once ready (or throws).
    public func start() async throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Flag()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = listener.port?.rawValue
                    if resumed.claim() { continuation.resume() }
                case .failed(let error):
                    if resumed.claim() { continuation.resume(throwing: error) }
                    else { self?.log("listener failed: \(error)") }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    // MARK: - Connections

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, parser: HTTPRequestParser())
    }

    private func receive(_ connection: NWConnection, parser: HTTPRequestParser) {
        var parser = parser
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            if error != nil { return connection.cancel() }
            switch parser.append(data ?? Data()) {
            case .incomplete:
                if isComplete { return connection.cancel() }
                self.receive(connection, parser: parser)
            case .error(let status):
                self.log("rejected malformed request: \(status)")
                self.send(HTTPResponseWriter.data(status: status), on: connection)
            case .request(let request):
                Task { self.send(await self.respond(to: request), on: connection) }
            }
        }
    }

    private func respond(to request: WireRequest) async -> Data {
        let decision = gate.decide(request)
        let status: Int
        let data: Data
        switch decision {
        case .respond(let s, let headers):
            status = s
            data = HTTPResponseWriter.data(status: s, headers: headers)
        case .allow(let cors):
            let response = await handler(HTTPRequest(method: request.method, headers: request.headers, body: request.body, path: request.path))
            status = response.statusCode
            data = HTTPResponseWriter.data(status: response.statusCode, headers: response.headers.merging(cors) { a, _ in a },
                                           body: response.bodyData ?? Data())
        }
        log("\(request.method) \(Self.redact(request.path)) → \(status) origin=\(request.headers["origin"] ?? "-") ua=\(request.headers["user-agent"] ?? "-")")
        return data
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Never log the token.
    static func redact(_ path: String) -> String {
        path.hasPrefix("/mcp/") ? "/mcp/<token>" : path
    }
}

/// One-shot flag shared with Network callbacks.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if set { return false }; set = true; return true }
}
