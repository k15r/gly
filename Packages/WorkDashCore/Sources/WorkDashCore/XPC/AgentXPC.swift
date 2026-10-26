import Foundation
import GRDB

/// XPC surface of the WorkDash agent (design L4): one method, JSON-encoded commands and results,
/// so new commands never change the XPC interface.
@objc public protocol WorkDashAgentXPC {
    func perform(_ command: Data, writer: String, reply: @escaping (Data) -> Void)
}

/// Agent side: decodes commands and runs them through the `CommandHandler`.
public final class AgentService: NSObject, WorkDashAgentXPC {
    private let handler: CommandHandler
    /// Answers `agentStatus` (agent process state that the store doesn't know).
    private let status: (() -> String)?
    /// Called on `reloadSettings`.
    private let reloadSettings: (() -> Void)?

    public init(writer: DatabaseWriter, status: (() -> String)? = nil, reloadSettings: (() -> Void)? = nil) {
        handler = CommandHandler(writer: writer)
        self.status = status
        self.reloadSettings = reloadSettings
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
    public init(service: AgentService, codeRequirement: String? = WorkDashIDs.teamCodeRequirement) {
        self.service = service
        self.codeRequirement = codeRequirement
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let codeRequirement { connection.setCodeSigningRequirement(codeRequirement) }
        connection.exportedInterface = NSXPCInterface(with: WorkDashAgentXPC.self)
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
            let c = NSXPCConnection(machServiceName: WorkDashIDs.agentMachService)
            c.setCodeSigningRequirement(WorkDashIDs.teamCodeRequirement)
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
        let timeout = self.timeout
        let connection = makeConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: WorkDashAgentXPC.self)
        connection.resume()
        defer { connection.invalidate() }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
            let once = Once()
            func finish(_ r: CommandResult) { if once.claim() { continuation.resume(returning: r) } }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                finish(.failure(CommandFailure(.unavailable, "WorkDash agent not reachable: \(error.localizedDescription)")))
            } as? WorkDashAgentXPC
            guard let proxy else {
                finish(.failure(CommandFailure(.unavailable, "WorkDash agent proxy unavailable")))
                return
            }
            proxy.perform(payload, writer: writer) { data in
                if let r = try? JSONDecoder().decode(CommandResult.self, from: data) { finish(r) }
                else { finish(.failure(CommandFailure(.internal, "Unreadable reply from the agent"))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(.failure(CommandFailure(.unavailable, "WorkDash agent did not answer within \(Int(timeout)) s")))
            }
        }
    }
}

/// Thread-safe one-shot flag.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
