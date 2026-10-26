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

do {
    let url = try StoreFactory.defaultDatabaseURL()
    let pool = try StoreFactory.openReadWrite(at: url)
    try pool.write { _ in }        // make sure the WAL file exists for the app's change watcher
    let settings = SharedSettings.shared()
    let calendar = EventKitSource()
    let tools = WorkDashTools(writer: pool, calendar: calendar,
                              hiddenCalendarIDs: { settings.hiddenCalendarIDs }, deviceID: settings.deviceID)
    let mcp = MCPHost()
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
        reloadSettings: { log.info("settings reloaded") },
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
