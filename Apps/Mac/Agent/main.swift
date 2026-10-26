// WorkDashAgent: launch agent inside WorkDash.app, registered as a login item.
// The only process that writes the store (design L2); reached over XPC by the app (and later the MCP shim).
import Foundation
import os
import WorkDashCore

let log = Logger(subsystem: "dev.k15r.workdash.agent", category: "agent")

do {
    let url = try StoreFactory.defaultDatabaseURL()
    let pool = try StoreFactory.openReadWrite(at: url)
    try pool.write { _ in }        // make sure the WAL file exists for the app's change watcher
    let calendar = EventKitSource()
    let delegate = AgentListenerDelegate(service: AgentService(writer: pool, status: {
        // Ask for calendar access in the background (a prompt may take longer than the XPC timeout); report the current state.
        if calendar.authorization == .notDetermined { Task { _ = await calendar.requestAccess() } }
        return "calendar: \(calendar.authorization)"
    }))
    let listener = NSXPCListener(machServiceName: WorkDashIDs.agentMachService)
    listener.delegate = delegate
    listener.resume()
    log.info("WorkDashAgent listening on \(WorkDashIDs.agentMachService, privacy: .public), store \(url.path, privacy: .public)")
    withExtendedLifetime(delegate) { RunLoop.main.run() }
} catch {
    log.fault("WorkDashAgent failed to start: \(String(describing: error), privacy: .public)")
    exit(1)
}
