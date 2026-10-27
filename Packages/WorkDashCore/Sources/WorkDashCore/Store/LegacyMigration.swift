import Foundation
import GRDB
import os

/// Takes over the WorkDash store and shared settings on gly's first start (rename-to-gly R2, specs/app-identity).
/// Runs in the agent before the store is opened; never writes to the WorkDash files.
public enum LegacyMigration {
    public struct Result: Equatable {
        public var copied = false
        public var items = 0
        public var tags = 0
        public var rewrittenTexts = 0
        public var settingsCopied = 0
    }

    /// Shared settings carried over (incl. the device id, so writer names in the history stay the same).
    static let settingKeys = ["deviceID", "hiddenCalendarIDs", "httpEnabled", "httpPort", "httpToken", "httpAllowedOrigins",
                              "workingStartMinute", "workingEndMinute", "effortMinutes", "horizonDays"]

    private static let log = Logger(subsystem: "dev.k15r.gly.agent", category: "migration")

    /// The real locations: gly's store and the WorkDash store in their app-group containers.
    public static func runForApp() throws -> Result {
        let newURL = try StoreFactory.defaultDatabaseURL()
        let legacyURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GlyIDs.Legacy.appGroup)?
            .appendingPathComponent(GlyIDs.Legacy.databaseFileName)
        return try run(newDatabase: newURL, legacyDatabase: legacyURL,
                       newDefaults: UserDefaults(suiteName: GlyIDs.appGroup), legacyDefaults: UserDefaults(suiteName: GlyIDs.Legacy.appGroup))
    }

    /// Copies only when gly has no store yet and a WorkDash store exists; otherwise does nothing.
    public static func run(newDatabase: URL, legacyDatabase: URL?, newDefaults: UserDefaults?, legacyDefaults: UserDefaults?) throws -> Result {
        var result = Result()
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newDatabase.path), let legacyDatabase, fm.fileExists(atPath: legacyDatabase.path) else { return result }

        // 1. Consistent copy via SQLite's online backup into a temp file, then an atomic rename into place.
        let temp = newDatabase.deletingLastPathComponent().appendingPathComponent(newDatabase.lastPathComponent + ".migrating")
        for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: temp.path + suffix) }
        var readOnly = Configuration(); readOnly.readonly = true
        let source = try DatabaseQueue(path: legacyDatabase.path, configuration: readOnly)
        do {
            let destination = try DatabaseQueue(path: temp.path)
            try source.backup(to: destination)
            try destination.close()
        }
        try source.close()
        try fm.moveItem(at: temp, to: newDatabase)
        result.copied = true

        // 2. Open with the current schema, point links at the new scheme (plain SQL: not a user change), rebuild the link and search index.
        let pool = try StoreFactory.openReadWrite(at: newDatabase)
        try pool.write { db in
            for (table, column) in [("items", "body"), ("tags", "page_body")] {
                try db.execute(sql: """
                    UPDATE \(table) SET \(column) = replace(\(column), '](workdash://', '](gly://') WHERE \(column) LIKE '%](workdash://%'
                    """)
                result.rewrittenTexts += db.changesCount
            }
            try DerivedIndex.rebuild(db)
            result.items = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items") ?? 0
            result.tags = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_tags") ?? 0
        }
        try pool.close()

        // 3. Shared settings, unless gly already has its own.
        if let newDefaults, let legacyDefaults, !settingKeys.contains(where: { newDefaults.object(forKey: $0) != nil }) {
            for key in settingKeys {
                if let value = legacyDefaults.object(forKey: key) { newDefaults.set(value, forKey: key); result.settingsCopied += 1 }
            }
            newDefaults.synchronize()
        }
        log.notice("took over WorkDash data: \(result.items) items, \(result.tags) tags, \(result.rewrittenTexts) texts with links rewritten, \(result.settingsCopied) settings")
        return result
    }
}
