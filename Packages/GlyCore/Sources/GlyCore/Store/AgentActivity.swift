import Foundation
import GRDB

/// One change made by an agent (MCP), for the app's "Recent agent changes" (mcp-server design M8).
public struct AgentChange: Equatable, Identifiable {
    public var id: String { batch }
    public let batch: String
    public let at: Date
    /// e.g. `agent:claude-code@mac-3f9a1c`
    public let writer: String
    /// e.g. `Create “Send report”`
    public let label: String
}

public enum AgentActivity {
    /// The most recent agent batches, newest first. Undo/redo batches are not listed.
    public static func recent(_ db: Database, limit: Int = 20) throws -> [AgentChange] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT batch, writer, MAX(at) AS at, MAX(seq) AS last FROM change_log
            WHERE writer LIKE 'agent:%' AND op IN ('insert', 'update', 'delete')
            GROUP BY batch ORDER BY last DESC LIMIT ?
            """, arguments: [limit])
        return try rows.map { r in
            AgentChange(batch: r["batch"], at: r["at"], writer: r["writer"], label: try db.label(ofBatch: r["batch"]))
        }
    }
}
