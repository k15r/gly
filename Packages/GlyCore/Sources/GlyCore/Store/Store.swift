import Foundation
import GRDB

/// Opens the gly database. The agent opens it read-write; the app read-only (design L2).
public enum StoreFactory {
    /// Location in the app group container shared by app and agent.
    public static func defaultDatabaseURL() throws -> URL {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GlyIDs.appGroup) else {
            throw StoreError.noAppGroupContainer
        }
        return dir.appendingPathComponent(GlyIDs.databaseFileName)
    }

    /// Read-write pool with migrations applied. Only the agent (and tests) use this.
    public static func openReadWrite(at url: URL) throws -> DatabasePool {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try Schema.migrator.migrate(pool)
        return pool
    }

    /// In-memory queue with migrations, for tests.
    public static func openInMemory() throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try Schema.migrator.migrate(queue)
        return queue
    }
}

public enum StoreError: Error, Equatable, CustomStringConvertible {
    case noAppGroupContainer
    case databaseMissing(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .noAppGroupContainer: return "The gly app group container is not available."
        case .databaseMissing(let path): return "The gly database does not exist yet at \(path)."
        case .notFound(let what): return "Not found: \(what)"
        }
    }
}
