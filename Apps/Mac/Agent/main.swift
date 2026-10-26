// WorkDashAgent: launch agent inside WorkDash.app, registered as a login item.
// The only process that writes the store (design L2); reached over XPC by the app and by `wd-mcp`,
// and hosts the MCP server (mcp-server design M1).
import Foundation
import os
import WorkDashCore
import WorkDashMCP

let log = Logger(subsystem: "dev.k15r.workdash.agent", category: "agent")

/// The MCP server is created asynchronously; messages arriving before that wait for it.
actor MCPHost {
    private var server: WorkDashMCPServer?
    private var waiters: [CheckedContinuation<WorkDashMCPServer, Never>] = []

    func set(_ server: WorkDashMCPServer) {
        self.server = server
        waiters.forEach { $0.resume(returning: server) }
        waiters = []
    }

    func get() async -> WorkDashMCPServer {
        if let server { return server }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

/// Runs the local HTTP endpoint according to the shared settings (design M6/M7); re-applied on `reloadSettings`.
actor HTTPController {
    let settings: SharedSettings
    let mcp: MCPHost
    private var server: LocalHTTPServer?
    private var running: (port: Int, token: String, origins: [String])?

    init(settings: SharedSettings, mcp: MCPHost) { self.settings = settings; self.mcp = mcp }

    func apply() async {
        settings.defaults.synchronize()
        guard settings.httpEnabled else {
            if server != nil { log.notice("HTTP endpoint off") }
            server?.stop(); server = nil; running = nil
            return
        }
        let wanted = (port: settings.httpPort, token: settings.httpToken, origins: settings.httpAllowedOrigins)
        if let running, running.port == wanted.port, running.token == wanted.token, running.origins == wanted.origins { return }
        server?.stop()
        let mcp = self.mcp
        let http = LocalHTTPServer(port: UInt16(wanted.port), gate: HTTPGate(token: wanted.token, allowedOrigins: wanted.origins),
                                   log: { log.notice("http: \($0, privacy: .public)") },
                                   handler: { await mcp.get().handle($0) })
        do {
            try await http.start()
            server = http
            running = wanted
            log.notice("HTTP endpoint on 127.0.0.1:\(wanted.port, privacy: .public)")
        } catch {
            server = nil; running = nil
            log.error("HTTP endpoint failed on port \(wanted.port, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    var state: String { running.map { "on (127.0.0.1:\($0.port))" } ?? "off" }
}

do {
    let url = try StoreFactory.defaultDatabaseURL()
    let pool = try StoreFactory.openReadWrite(at: url)
    try pool.write { _ in }        // make sure the WAL file exists for the app's change watcher
    let settings = SharedSettings.shared()
    let calendar = EventKitSource()
    let tools = WorkDashTools(writer: pool, calendar: calendar,
                              hiddenCalendarIDs: { settings.hiddenCalendarIDs }, deviceID: settings.deviceID)
    let mcp = MCPHost()
    let http = HTTPController(settings: settings, mcp: mcp)
    Task { await http.apply() }
    Task {
        do { await mcp.set(try await WorkDashMCPServer(tools: tools)) }
        catch { log.fault("MCP server failed to start: \(String(describing: error), privacy: .public)") }
    }
    let service = AgentService(
        writer: pool,
        status: {
            // Ask for calendar access in the background (a prompt may take longer than the XPC timeout); report the current state.
            if calendar.authorization == .notDetermined { Task { _ = await calendar.requestAccess() } }
            return "calendar: \(calendar.authorization)"
        },
        reloadSettings: { Task { await http.apply() } },
        mcp: { message, client in await mcp.get().handleStdio(message, client: client) })
    let delegate = AgentListenerDelegate(service: service)
    let listener = NSXPCListener(machServiceName: WorkDashIDs.agentMachService)
    listener.delegate = delegate
    listener.resume()
    log.info("WorkDashAgent listening on \(WorkDashIDs.agentMachService, privacy: .public), store \(url.path, privacy: .public)")
    withExtendedLifetime(delegate) { RunLoop.main.run() }
} catch {
    log.fault("WorkDashAgent failed to start: \(String(describing: error), privacy: .public)")
    exit(1)
}
