import GRDB

/// Database schema. Migrations are additive only: never rename or drop columns
/// (sync-ready conventions, foundation-spikes D2/D3a).
public enum Schema {
    /// Tables that will be synced later; every one carries the sync columns.
    public static let syncedTables = ["items", "tags", "item_tags"]

    public static let itemKinds = ["info", "task", "event_note", "local_event"]
    public static let taskStatuses = ["open", "snoozed", "done", "dropped"]
    public static let priorities = ["none", "low", "normal", "high", "urgent"]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createV1(db)
        }
        return migrator
    }

    /// Sync columns (D2): UUID id, timestamps, writer, tombstone.
    private static func syncColumns(_ t: TableDefinition) {
        t.primaryKey("id", .text)
        t.column("created_at", .datetime).notNull()
        t.column("modified_at", .datetime).notNull()
        t.column("modified_by", .text).notNull()
        t.column("deleted_at", .datetime)
    }

    private static func createV1(_ db: Database) throws {
        // One table for all item kinds (D3); only `task` is used in this version.
        try db.create(table: "items") { t in
            syncColumns(t)
            t.column("kind", .text).notNull().check { itemKinds.contains($0) }
            t.column("title", .text).notNull().check { length($0) > 0 }
            t.column("body", .text).notNull().defaults(to: "")
            t.column("status", .text).check { $0 == nil || taskStatuses.contains($0) }
            t.column("priority", .text).check { $0 == nil || priorities.contains($0) }
            // Floating local dates: "this calendar day, wherever I am" (design L3).
            t.column("due_day", .text)          // YYYY-MM-DD
            t.column("due_time", .text)         // HH:mm, optional
            t.column("snoozed_until", .text)    // YYYY-MM-DD
            t.column("completed_at", .datetime)
        }
        try db.create(index: "items_kind_status", on: "items", columns: ["kind", "status", "deleted_at"])
        try db.create(index: "items_due_day", on: "items", columns: ["due_day"])

        try db.create(table: "tags") { t in
            syncColumns(t)
            t.column("name", .text).notNull()        // display casing as first entered
            t.column("name_key", .text).notNull()    // case-folded, used for identity and filtering
            t.column("color", .text)
            t.column("page_body", .text).notNull().defaults(to: "")
            t.column("archived", .boolean).notNull().defaults(to: false)
        }
        // Unique among live tags only; sync may still deliver duplicates, merged later (D3a).
        try db.execute(sql: "CREATE UNIQUE INDEX tags_name_key_live ON tags(name_key) WHERE deleted_at IS NULL")

        // Tag assignments as rows of their own (D3): concurrent tagging merges per assignment.
        try db.create(table: "item_tags") { t in
            syncColumns(t)
            t.column("item_id", .text).notNull().references("items")
            t.column("tag_id", .text).notNull().references("tags")
        }
        try db.create(index: "item_tags_item", on: "item_tags", columns: ["item_id"])
        try db.create(index: "item_tags_tag", on: "item_tags", columns: ["tag_id"])

        // History, undo/redo and later the sync outbox (D2). Local only.
        try db.create(table: "change_log") { t in
            t.autoIncrementedPrimaryKey("seq")
            t.column("at", .datetime).notNull()
            t.column("writer", .text).notNull()
            t.column("batch", .text).notNull()
            t.column("op", .text).notNull().check { ["insert", "update", "delete", "undo", "redo"].contains($0) }
            t.column("table_name", .text).notNull()
            t.column("row_id", .text).notNull()
            t.column("field", .text)
            t.column("old_value", .text)
            t.column("new_value", .text)
            t.column("synced", .boolean).notNull().defaults(to: false)
            t.column("undone", .boolean).notNull().defaults(to: false)
            t.column("redo_of", .text)      // batch id this redo re-applies
        }
        try db.create(index: "change_log_batch", on: "change_log", columns: ["batch"])
        try db.create(index: "change_log_writer", on: "change_log", columns: ["writer", "seq"])

        for table in syncedTables {
            try db.execute(sql: "CREATE VIEW live_\(table) AS SELECT * FROM \(table) WHERE deleted_at IS NULL")
        }
    }
}
