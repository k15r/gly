// Spike 3 (foundation-spikes): WorkDash agent (launch agent / login item). Owns the store. Throwaway code.
import Foundation
import GRDB
import os
import StoreSpike

let log = Logger(subsystem: "dev.k15r.workdash.agent", category: "xpc")

final class Agent: NSObject, AgentXPC {
    func ping(reply: @escaping (String) -> Void) {
        reply("pong from WorkDashAgent pid \(getpid())")
    }

    /// Real data from the Spike 2 store in the app group container (task 4.5):
    /// local appointments starting that day + open tasks due that day, each with its tags.
    func getSchedule(_ date: String, reply: @escaping (String) -> Void) {
        do {
            let pool = try Store_.shared()
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
            guard let day = f.date(from: date) else { return reply(#"{"error":"bad date \#(date)"}"#) }
            let next = day.addingTimeInterval(86_400)
            let payload: [String: Any] = try pool.read { db in
                func tags(_ id: String) throws -> [String] {
                    try String.fetchAll(db, sql: "SELECT t.name FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE it.item_id = ? ORDER BY t.name", arguments: [id])
                }
                let iso = ISO8601DateFormatter()
                let events = try Row.fetchAll(db, sql: """
                    SELECT id, title, start_at, end_at FROM live_items
                    WHERE kind = 'local_event' AND start_at >= ? AND start_at < ? ORDER BY start_at
                    """, arguments: [day, next]).map { r -> [String: Any] in
                    ["id": r["id"] as String, "title": r["title"] as String, "calendar": "WorkDash/local",
                     "start": iso.string(from: r["start_at"]), "end": iso.string(from: r["end_at"]), "tags": try tags(r["id"])]
                }
                let tasks = try Row.fetchAll(db, sql: """
                    SELECT id, title, priority, due FROM live_items
                    WHERE kind = 'task' AND status = 'open' AND due >= ? AND due < ? ORDER BY due
                    """, arguments: [day, next]).map { r -> [String: Any] in
                    ["id": r["id"] as String, "title": r["title"] as String, "priority": r["priority"] as String? ?? "none",
                     "due": iso.string(from: r["due"]), "tags": try tags(r["id"])]
                }
                return ["date": date, "source": "store", "events": events, "tasks_due": tasks,
                        "store_items_total": try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items") ?? 0]
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            reply(String(data: data, encoding: .utf8)!)
        } catch {
            log.error("getSchedule failed: \(String(describing: error))")
            reply(#"{"error":"\#(String(describing: error).replacingOccurrences(of: "\"", with: "'"))"}"#)
        }
    }
}

/// The agent is the single owner of the store (D5 option Y). Lives in the app group container.
enum Store_ {
    static let lock = NSLock()
    static var pool: DatabasePool?
    static func shared() throws -> DatabasePool {
        lock.lock(); defer { lock.unlock() }
        if let p = pool { return p }
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DB33H6YGK7.dev.k15r.workdash") else {
            throw DatabaseError(message: "no app group container")
        }
        let path = dir.appendingPathComponent("workdash-spike.sqlite").path
        let p = try DatabasePool(path: path)
        try Schema.migrator.migrate(p)
        if try p.read({ try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM items") ?? 0 }) == 0 {
            var cfg = GeneratorConfig(); cfg.now = Date()          // fixture around today so get_schedule has data
            _ = try p.write { try $0.generate(cfg) }
            log.info("generated fixture into \(path)")
        }
        pool = p
        return p
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.setCodeSigningRequirement(teamCodeRequirement)   // reject processes not signed by our team
        c.exportedInterface = NSXPCInterface(with: AgentXPC.self)
        c.exportedObject = Agent()
        c.resume()
        log.info("accepted connection from pid \(c.processIdentifier)")
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: agentMachServiceName)
listener.delegate = delegate
listener.resume()
log.info("WorkDashAgent listening on \(agentMachServiceName)")
RunLoop.main.run()
