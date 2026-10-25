// Spike 2 (foundation-spikes): D3 schema with D2 conventions. Throwaway code.
import GRDB

/// Tables that sync later. Every one carries the D2 columns.
public let syncedTables = [
    "items", "tags", "item_tags", "links",
    "property_keys", "property_values", "templates", "recurrences",
]

public enum Schema {
    public static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1-core") { db in
            /// D2: uuid id, timestamps, writer, tombstone.
            func syncColumns(_ t: TableDefinition) {
                t.primaryKey("id", .text)                       // UUID string, never auto-increment
                t.column("created_at", .datetime).notNull()
                t.column("modified_at", .datetime).notNull()
                t.column("modified_by", .text).notNull()       // "user@<device>" | "agent:<name>"
                t.column("deleted_at", .datetime)              // tombstone; NULL = alive
            }

            // One table for all item kinds (D3). Kind-specific columns are nullable.
            try db.create(table: "recurrences") { t in
                syncColumns(t)
                t.column("template_title", .text).notNull()
                t.column("template_body", .text)
                t.column("template_priority", .text)
                t.column("rule", .text).notNull()              // e.g. "FREQ=WEEKLY;BYDAY=FR"
                t.column("model", .text).notNull()
                    .check { ["fixed", "after_completion", "after_event"].contains($0) }
                t.column("missed_policy", .text).notNull()
                    .check { ["pile_up", "replace"].contains($0) }
                t.column("series_ref", .text)                  // calendar series for after_event
            }

            try db.create(table: "items") { t in
                syncColumns(t)
                t.column("kind", .text).notNull()
                    .check { ["info", "task", "event_note", "local_event"].contains($0) }
                t.column("title", .text).notNull()
                t.column("body", .text).notNull().defaults(to: "")
                // task
                t.column("status", .text)
                    .check { $0 == nil || ["inbox", "open", "snoozed", "done", "dropped"].contains($0) }
                t.column("priority", .text)
                    .check { $0 == nil || ["none", "low", "normal", "high", "urgent"].contains($0) }
                t.column("due", .datetime)
                t.column("snoozed_until", .datetime)
                t.column("needs_input", .text)
                t.column("source", .text)                      // JSON: {type, message_id, thread_id, ...}
                t.column("source_message_id", .text)           // denormalized for dedup lookups
                t.column("recurrence_id", .text).references("recurrences", onDelete: .setNull)
                // event_note (D4)
                t.column("event_key", .text)
                t.column("event_snapshot", .text)              // JSON: title, start, end, calendar, organizer
                t.column("event_status", .text)
                    .check { $0 == nil || ["active", "cancelled", "gone"].contains($0) }
                // local_event
                t.column("start_at", .datetime)
                t.column("end_at", .datetime)
            }
            try db.create(index: "items_kind", on: "items", columns: ["kind", "deleted_at"])
            try db.create(index: "items_due", on: "items", columns: ["due"])
            try db.create(index: "items_event_key", on: "items", columns: ["event_key"])
            try db.create(index: "items_source_message_id", on: "items", columns: ["source_message_id"])

            try db.create(table: "tags") { t in
                syncColumns(t)
                t.column("name", .text).notNull()              // hierarchy via "/", e.g. "person/alex"
                t.column("color", .text)
                t.column("page_body", .text).notNull().defaults(to: "")
                t.column("archived", .boolean).notNull().defaults(to: false)
            }
            // Unique among live tags only. With sync, duplicates can still arrive and need a merge pass.
            try db.execute(sql: "CREATE UNIQUE INDEX tags_name_live ON tags(name) WHERE deleted_at IS NULL")

            // Tag assignment as its own row (D3) so concurrent tagging merges per assignment.
            try db.create(table: "item_tags") { t in
                syncColumns(t)
                t.column("item_id", .text).notNull().references("items", onDelete: .cascade)
                t.column("tag_id", .text).notNull().references("tags", onDelete: .cascade)
            }
            try db.create(index: "item_tags_item", on: "item_tags", columns: ["item_id"])
            try db.create(index: "item_tags_tag", on: "item_tags", columns: ["tag_id"])

            try db.create(table: "links") { t in
                syncColumns(t)
                t.column("from_id", .text).notNull()           // item or tag id; target may be gone (sync)
                t.column("to_id", .text).notNull()
                t.column("type", .text)
            }
            try db.create(index: "links_from", on: "links", columns: ["from_id"])
            try db.create(index: "links_to", on: "links", columns: ["to_id"])

            try db.create(table: "property_keys") { t in
                syncColumns(t)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                    .check { ["text", "number", "date", "bool", "list", "link"].contains($0) }
            }
            try db.execute(sql: "CREATE UNIQUE INDEX property_keys_name_live ON property_keys(name) WHERE deleted_at IS NULL")

            // Typed columns: exactly one is set, chosen by the key's type (D3).
            try db.create(table: "property_values") { t in
                syncColumns(t)
                t.column("owner_id", .text).notNull()          // item or tag
                t.column("owner_kind", .text).notNull().check { ["item", "tag"].contains($0) }
                t.column("key_id", .text).notNull().references("property_keys", onDelete: .cascade)
                t.column("text_value", .text)                  // text; list = JSON array
                t.column("number_value", .double)
                t.column("date_value", .datetime)
                t.column("bool_value", .boolean)
                t.column("ref_value", .text)                   // link: item or tag id
            }
            try db.create(index: "property_values_owner", on: "property_values", columns: ["owner_id"])
            try db.create(index: "property_values_key_date", on: "property_values", columns: ["key_id", "date_value"])
            try db.create(index: "property_values_key_number", on: "property_values", columns: ["key_id", "number_value"])
            try db.create(index: "property_values_key_text", on: "property_values", columns: ["key_id", "text_value"])

            try db.create(table: "templates") { t in
                syncColumns(t)
                t.column("prefix", .text)                      // e.g. "person/"; or tag_id
                t.column("tag_id", .text).references("tags", onDelete: .cascade)
                t.column("key_ids", .text).notNull()           // JSON array of property_keys ids
            }

            // History + undo + later sync outbox (D2). Local only, so an integer sequence is fine.
            try db.create(table: "change_log") { t in
                t.autoIncrementedPrimaryKey("seq")
                t.column("at", .datetime).notNull()
                t.column("writer", .text).notNull()
                t.column("batch", .text).notNull()             // one logical change (undo unit)
                t.column("op", .text).notNull().check { ["insert", "update", "delete", "undo"].contains($0) }
                t.column("table_name", .text).notNull()
                t.column("row_id", .text).notNull()
                t.column("field", .text)                       // NULL for whole-row insert/delete
                t.column("old_value", .text)                   // JSON-encoded
                t.column("new_value", .text)
                t.column("synced", .boolean).notNull().defaults(to: false)
                t.column("undone", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "change_log_row", on: "change_log", columns: ["table_name", "row_id"])
            try db.create(index: "change_log_batch", on: "change_log", columns: ["batch"])

            // Reads go through live views so tombstones can't leak into queries (D2).
            for table in syncedTables {
                try db.execute(sql: "CREATE VIEW live_\(table) AS SELECT * FROM \(table) WHERE deleted_at IS NULL")
            }
        }
        // FTS5 external-content indexes (D3): items title/body and tag pages.
        // unicode61 with remove_diacritics 2: "Prufung" matches "Prüfung". Prefix indexes speed up "budg*".
        m.registerMigration("v2-fts") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE items_fts USING fts5(
                    title, body, content='items', content_rowid='rowid',
                    tokenize='unicode61 remove_diacritics 2', prefix='2 3 4');
                CREATE VIRTUAL TABLE tags_fts USING fts5(
                    name, page_body, content='tags', content_rowid='rowid',
                    tokenize='unicode61 remove_diacritics 2', prefix='2 3 4');
                """)
            for (table, cols) in [("items", ["title", "body"]), ("tags", ["name", "page_body"])] {
                let list = cols.joined(separator: ", ")
                let new = cols.map { "new.\($0)" }.joined(separator: ", ")
                let old = cols.map { "old.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    CREATE TRIGGER \(table)_fts_ai AFTER INSERT ON \(table) BEGIN
                      INSERT INTO \(table)_fts(rowid, \(list)) VALUES (new.rowid, \(new));
                    END;
                    CREATE TRIGGER \(table)_fts_ad AFTER DELETE ON \(table) BEGIN
                      INSERT INTO \(table)_fts(\(table)_fts, rowid, \(list)) VALUES ('delete', old.rowid, \(old));
                    END;
                    CREATE TRIGGER \(table)_fts_au AFTER UPDATE OF \(list) ON \(table) BEGIN
                      INSERT INTO \(table)_fts(\(table)_fts, rowid, \(list)) VALUES ('delete', old.rowid, \(old));
                      INSERT INTO \(table)_fts(rowid, \(list)) VALUES (new.rowid, \(new));
                    END;
                    INSERT INTO \(table)_fts(\(table)_fts) VALUES ('rebuild');
                    """)
            }
        }
        return m
    }
}

extension Store {
    public func migrate() throws {
        try Schema.migrator.migrate(db)
    }
}
