import GRDB

/// Database schema. Migrations are additive only: never rename or drop columns
/// (sync-ready conventions, foundation-spikes D2/D3a).
public enum Schema {
    /// Tables that will be synced later; every one carries the sync columns.
    public static let syncedTables = ["items", "tags", "item_tags", "series_rules", "task_work", "views"]

    /// Removes every row of user data, the change log and the derived indexes; the schema stays (Settings → Data).
    /// Dependents first, so references never point at removed rows mid-way.
    static func eraseAllData(_ db: Database) throws {
        for table in ["views", "task_parts", "task_work", "item_tags", "series_rules", "items", "tags", "change_log", "link_index", "search_index"] {
            try db.execute(sql: "DELETE FROM \(table)")
        }
        try db.execute(sql: "DELETE FROM sqlite_sequence WHERE name = 'change_log'")
    }
    public static let efforts = ["XS", "S", "M", "L", "XL"]
    /// task_work kinds: "done for today", a set remaining effort, work recorded by an agent.
    public static let workKinds = ["part", "adjust", "agent"]
    public static let eventStates = ["active", "cancelled", "gone", "ambiguous"]
    public static let blockingValues = ["blocks", "optional", "ignore"]

    public static let itemKinds = ["info", "task", "event_note", "local_event", "bookmark"]
    public static let taskStatuses = ["open", "snoozed", "done", "dropped"]
    public static let priorities = ["none", "low", "normal", "high", "urgent"]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createV1(db)
        }
        migrator.registerMigration("v2") { db in
            try createV2(db)
        }
        // Re-derive the search text once after LinkParser.plainText started stripping web-link markup.
        migrator.registerMigration("v3-rebuild-derived") { db in
            try DerivedIndex.rebuild(db)
        }
        migrator.registerMigration("v4") { db in
            try createV4(db)
        }
        // Series notes (meeting-pages N1): the series rule a series notes document belongs to.
        migrator.registerMigration("v5") { db in
            try db.alter(table: "items") { t in t.add(column: "series_rule", .text) }
            try db.create(index: "items_series_rule", on: "items", columns: ["series_rule"])
        }
        // The day a task came back from a snooze, for the "back from snooze" mark (future-day-planning F3).
        migrator.registerMigration("v6") { db in
            try db.alter(table: "items") { t in t.add(column: "snooze_ended_on", .text) }    // YYYY-MM-DD
        }
        // Work recorded on tasks; remaining effort = effort - sum (task-progress P1).
        migrator.registerMigration("v7") { db in
            try db.create(table: "task_work") { t in
                syncColumns(t)
                t.column("item_id", .text).notNull().references("items")
                t.column("day", .text).notNull()                        // YYYY-MM-DD
                t.column("minutes", .integer).notNull()                  // negative = more left than before (an adjustment)
                t.column("kind", .text).notNull().check { workKinds.contains($0) }
            }
            try db.create(index: "task_work_item", on: "task_work", columns: ["item_id"])
            try db.execute(sql: "CREATE VIEW live_task_work AS SELECT * FROM task_work WHERE deleted_at IS NULL")
        }
        // A first version of subtasks stored parts in a table; parts are now the checklist items of the notes
        // (subtasks S3). Kept because migrations are additive; the table stays empty and isn't synced.
        migrator.registerMigration("v8") { db in
            try db.create(table: "task_parts") { t in
                syncColumns(t)
                t.column("item_id", .text).notNull().references("items")
                t.column("position", .double).notNull()
                t.column("title", .text).notNull().check { length($0) > 0 }
                t.column("effort", .text).check { $0 == nil || efforts.contains($0) }
                t.column("done_at", .datetime)
            }
            try db.create(index: "task_parts_item", on: "task_parts", columns: ["item_id", "position"])
            try db.execute(sql: "CREATE VIEW live_task_parts AS SELECT * FROM task_parts WHERE deleted_at IS NULL")
        }
        // Bookmarks are items (bookmarks B1): `bookmark` joins the kind check, which SQLite can only change by
        // rebuilding the table; rows, columns, indexes and views stay the same. Foreign keys are checked at the end.
        migrator.registerMigration("v9") { db in
            try rebuildItems(db)
            try db.alter(table: "items") { t in t.add(column: "url", .text) }
            try db.execute(sql: "CREATE UNIQUE INDEX items_bookmark_url ON items(url) WHERE kind = 'bookmark' AND deleted_at IS NULL")
        }
        // Saved views of the item browser (item-browser I3): kept with the data, so they are undoable and agents can manage them.
        migrator.registerMigration("v10") { db in
            try db.create(table: "views") { t in
                syncColumns(t)
                t.column("name", .text).notNull().check { length($0) > 0 }
                t.column("symbol", .text).notNull().defaults(to: "line.3.horizontal.decrease.circle")
                t.column("query", .text).notNull().defaults(to: "")      // ItemQuery text form
                t.column("grouping", .text).notNull().defaults(to: "none")
                t.column("sort", .text).notNull().defaults(to: "changed")
                t.column("position", .double).notNull().defaults(to: 0)
            }
            try db.execute(sql: "CREATE VIEW live_views AS SELECT * FROM views WHERE deleted_at IS NULL")
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

    /// Recreates `items` with the kind check of `itemKinds`: same columns and rows, then the indexes and the views
    /// that read `items` again.
    private static func rebuildItems(_ db: Database) throws {
        let table = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'items'") ?? ""
        let check = #"CHECK \("kind" IN \([^)]*\)\)"#
        guard table.range(of: check, options: .regularExpression) != nil else { throw DatabaseError(message: "items: no kind check") }
        let kinds = itemKinds.map { "'\($0)'" }.joined(separator: ", ")
        let newTable = table
            .replacingOccurrences(of: check, with: "CHECK (\"kind\" IN (\(kinds)))", options: .regularExpression)
            .replacingOccurrences(of: #"CREATE TABLE "items""#, with: #"CREATE TABLE "items_new""#)
        let indexes = try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'items' AND sql IS NOT NULL")
        let views = try Row.fetchAll(db, sql: "SELECT name, sql FROM sqlite_master WHERE type = 'view' AND sql LIKE '%items%'")
            .map { (name: $0["name"] as String, sql: $0["sql"] as String) }
        for view in views { try db.execute(sql: "DROP VIEW \(view.name.quotedDatabaseIdentifier)") }
        try db.execute(sql: newTable)
        try db.execute(sql: "INSERT INTO items_new SELECT * FROM items")
        try db.execute(sql: "DROP TABLE items")
        try db.execute(sql: "ALTER TABLE items_new RENAME TO items")
        for sql in indexes + views.map(\.sql) { try db.execute(sql: sql) }
    }

    private static func createV1(_ db: Database) throws {
        // One table for all item kinds (D3); only `task` is used in this version. The kind list is that of v1;
        // later kinds come with the v9 rebuild.
        try db.create(table: "items") { t in
            syncColumns(t)
            t.column("kind", .text).notNull().check { ["info", "task", "event_note", "local_event"].contains($0) }
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
            t.column("color", .text)                 // a TagColor name (tag-colors C1); nil = inherit / automatic
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

        // Frozen list: tables added later create their own views in their migration.
        for table in ["items", "tags", "item_tags"] {
            try db.execute(sql: "CREATE VIEW live_\(table) AS SELECT * FROM \(table) WHERE deleted_at IS NULL")
        }
    }

    /// Planning (planning-day-view design Q3): task effort, appointment annotations, series rules.
    private static func createV4(_ db: Database) throws {
        try db.alter(table: "items") { t in
            t.add(column: "effort", .text).check { $0 == nil || efforts.contains($0) }
            // Appointment annotations (kind = 'event_note'): key, snapshot, life-cycle state, blocking override.
            t.add(column: "event_key", .text)
            t.add(column: "event_series", .text)
            t.add(column: "event_calendar", .text)
            t.add(column: "event_start", .datetime)
            t.add(column: "event_end", .datetime)
            t.add(column: "event_organizer", .text)
            t.add(column: "event_state", .text).check { $0 == nil || eventStates.contains($0) }
            t.add(column: "blocking", .text).check { $0 == nil || blockingValues.contains($0) }
        }
        try db.create(index: "items_event_key", on: "items", columns: ["event_key"])
        try db.create(index: "items_event_start", on: "items", columns: ["event_start"])

        try db.create(table: "series_rules") { t in
            syncColumns(t)
            t.column("calendar_id", .text).notNull()
            t.column("title", .text).notNull()
            t.column("organizer", .text)
            t.column("base_ids", .text).notNull().defaults(to: "[]")   // JSON array; grows when a series is split
            t.column("blocking", .text).check { $0 == nil || blockingValues.contains($0) }
        }
        try db.execute(sql: "CREATE VIEW live_series_rules AS SELECT * FROM series_rules WHERE deleted_at IS NULL")
    }

    /// Pages and links (info-pages-and-links design P2, P6). Local-only, derived tables; not in `syncedTables`.
    private static func createV2(_ db: Database) throws {
        // Edit sessions: saves of one text field in one session coalesce into one undo step.
        try db.alter(table: "change_log") { t in t.add(column: "session", .text) }

        try db.create(table: "link_index") { t in
            t.autoIncrementedPrimaryKey("seq")
            t.column("source_table", .text).notNull()       // items | tags
            t.column("source_id", .text).notNull()
            t.column("target_kind", .text).notNull().check { ["item", "tag", "missing"].contains($0) }
            t.column("target_id", .text)                     // item/tag id (uppercased UUID)
            t.column("missing_title", .text)                 // [[Title]] as typed
            t.column("missing_key", .text)                   // case-folded, for resolution
            t.column("range_location", .integer).notNull()   // UTF-16 offsets in the source text
            t.column("range_length", .integer).notNull()
        }
        try db.create(index: "link_index_source", on: "link_index", columns: ["source_table", "source_id"])
        try db.create(index: "link_index_target", on: "link_index", columns: ["target_kind", "target_id"])
        try db.create(index: "link_index_missing", on: "link_index", columns: ["missing_key"])

        try db.execute(sql: """
            CREATE VIRTUAL TABLE search_index USING fts5(
                owner_table UNINDEXED, owner_id UNINDEXED, kind UNINDEXED, title, text,
                tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3 4')
            """)
        try DerivedIndex.rebuild(db)
    }
}
