import Foundation
import GRDB
@testable import WorkDashCore

/// Test helper: inserts a task with tags directly through the change log (no command validation).
@discardableResult
func addTask(_ db: Database, _ title: String, tags: [String] = [], status: String = "open", priority: String = "none",
             dueDay: String? = nil, dueTime: String? = nil, snoozedUntil: String? = nil,
             createdAt: Date = Date(), writer: String = "user@test") throws -> String {
    let b = Batch(db: db, writer: writer, at: createdAt)
    let id = try b.insert("items", ["kind": "task", "title": title, "status": status, "priority": priority,
                                    "due_day": dueDay, "due_time": dueTime, "snoozed_until": snoozedUntil])
    for raw in tags {
        let name = try TagName(raw)
        let tagID = try String.fetchOne(db, sql: "SELECT id FROM live_tags WHERE name_key = ?", arguments: [name.key])
            ?? b.insert("tags", ["name": name.display, "name_key": name.key])
        try b.insert("item_tags", ["item_id": id, "tag_id": tagID])
    }
    return id
}
