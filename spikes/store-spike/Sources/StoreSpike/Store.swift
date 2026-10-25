// Spike 2 (foundation-spikes): GRDB/SQLite store. Throwaway code.
import GRDB

public struct Store {
    public let db: DatabaseQueue

    public init(path: String? = nil) throws {
        db = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
    }
}
