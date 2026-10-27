import Foundation
import GRDB

/// XPC surface of the gly agent (design L4): one method, JSON-encoded commands and results,
/// so new commands never change the XPC interface.
@objc public protocol GlyAgentXPC {
    func perform(_ command: Data, writer: String, reply: @escaping (Data) -> Void)
    /// One MCP JSON-RPC message from `gly-mcp` (design M1); the reply is nil for notifications.
    func mcp(_ message: Data, client: String?, reply: @escaping (Data?) -> Void)
}

/// Agent side: decodes commands and runs them through the `CommandHandler`.
public final class AgentService: NSObject, GlyAgentXPC {
    private let handler: CommandHandler
    /// Answers `agentStatus` (agent process state that the store doesn't know).
    private let status: (() -> String)?
    /// Called on `reloadSettings`.
    private let reloadSettings: (() -> Void)?
    /// Handles MCP messages (the agent's MCP server); nil = MCP not offered.
    private let mcpHandler: (@Sendable (Data, String?) async -> Data?)?

    public init(writer: DatabaseWriter, status: (() -> String)? = nil, reloadSettings: (() -> Void)? = nil,
                mcp: (@Sendable (Data, String?) async -> Data?)? = nil) {
        handler = CommandHandler(writer: writer)
        self.status = status
        self.reloadSettings = reloadSettings
        self.mcpHandler = mcp
    }

    public func mcp(_ message: Data, client: String?, reply: @escaping (Data?) -> Void) {
        guard let mcpHandler else { return reply(nil) }
        let reply = UncheckedSendable(reply)
        Task { reply.value(await mcpHandler(message, client)) }
    }

    public func perform(_ command: Data, writer: String, reply: @escaping (Data) -> Void) {
        let result: CommandResult
        do {
            let decoded = try JSONDecoder().decode(Command.self, from: command)
            if decoded == .agentStatus, let status {
                result = .ok(CommandOK(changed: false, message: status()))
            } else if decoded == .reloadSettings {
                reloadSettings?()
                result = .ok(CommandOK(changed: false))
            } else {
                result = handler.perform(decoded, writer: writer)
            }
        } catch {
            result = .failure(CommandFailure(.validation, "Unreadable command: \(error)"))
        }
        reply((try? JSONEncoder().encode(result)) ?? Data())
    }
}

/// Listener delegate used by the agent (Mach service) and by tests (anonymous listener).
public final class AgentListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: AgentService
    private let codeRequirement: String?

    /// - Parameter codeRequirement: required peer signature; nil only in tests.
    public init(service: AgentService, codeRequirement: String? = GlyIDs.teamCodeRequirement) {
        self.service = service
        self.codeRequirement = codeRequirement
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let codeRequirement { connection.setCodeSigningRequirement(codeRequirement) }
        connection.exportedInterface = NSXPCInterface(with: GlyAgentXPC.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

/// App side: sends commands to the agent, with a timeout and clear errors when it isn't reachable.
public final class AgentClient {
    private let makeConnection: () -> NSXPCConnection
    private let timeout: TimeInterval

    /// Connects to the agent's Mach service (production).
    public convenience init(timeout: TimeInterval = 5) {
        self.init(timeout: timeout) {
            let c = NSXPCConnection(machServiceName: GlyIDs.agentMachService)
            c.setCodeSigningRequirement(GlyIDs.teamCodeRequirement)
            return c
        }
    }

    /// Connects to a listener endpoint (tests).
    public convenience init(endpoint: NSXPCListenerEndpoint, timeout: TimeInterval = 5) {
        self.init(timeout: timeout) { NSXPCConnection(listenerEndpoint: endpoint) }
    }

    init(timeout: TimeInterval, makeConnection: @escaping () -> NSXPCConnection) {
        self.timeout = timeout
        self.makeConnection = makeConnection
    }

    public func perform(_ command: Command, writer: String) async -> CommandResult {
        let payload: Data
        do { payload = try JSONEncoder().encode(command) } catch {
            return .failure(CommandFailure(.internal, "Could not encode command: \(error)"))
        }
        let result: Result<CommandResult, CommandFailure> = await call(timeout: timeout) { proxy, finish in
            proxy.perform(payload, writer: writer) { data in
                if let r = try? JSONDecoder().decode(CommandResult.self, from: data) { finish(.success(r)) }
                else { finish(.failure(CommandFailure(.internal, "Unreadable reply from the agent"))) }
            }
        }
        switch result {
        case .success(let r): return r
        case .failure(let f): return .failure(f)
        }
    }

    /// Sends one MCP message (used by `gly-mcp`). Success with nil = notification without reply.
    public func mcp(_ message: Data, client: String?, timeout: TimeInterval = 30) async -> Result<Data?, CommandFailure> {
        await call(timeout: timeout) { proxy, finish in
            proxy.mcp(message, client: client) { finish(.success($0)) }
        }
    }

    /// One XPC round trip with a timeout; connection errors become `.unavailable`.
    private func call<T>(timeout: TimeInterval,
                         _ body: @escaping (GlyAgentXPC, @escaping (Result<T, CommandFailure>) -> Void) -> Void) async -> Result<T, CommandFailure> {
        let connection = makeConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: GlyAgentXPC.self)
        connection.resume()
        defer { connection.invalidate() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, CommandFailure>, Never>) in
            let once = Once()
            let finish: (Result<T, CommandFailure>) -> Void = { r in if once.claim() { continuation.resume(returning: r) } }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                finish(.failure(CommandFailure(.unavailable, "gly agent not reachable: \(error.localizedDescription)")))
            } as? GlyAgentXPC
            guard let proxy else {
                finish(.failure(CommandFailure(.unavailable, "gly agent proxy unavailable")))
                return
            }
            body(proxy, finish)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(CommandFailure(.unavailable, "gly agent did not answer within \(Int(timeout)) s")))
            }
        }
    }
}

/// Wraps a non-Sendable value (XPC reply blocks are safe to call from any thread).
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Thread-safe one-shot flag.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
