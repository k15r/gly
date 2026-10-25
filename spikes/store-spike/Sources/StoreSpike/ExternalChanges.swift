// Spike 2 (foundation-spikes): make ValueObservation notice writes from other processes. Throwaway code.
// GRDB only observes writes made through its own connections. For writes by another process
// (sqlite3 CLI, a separate MCP helper) we watch the WAL file and tell GRDB via notifyChanges(in:).
import Foundation
import GRDB

public final class ExternalChangeWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "external-change-watcher")

    public init(pool: DatabasePool, path: String) throws {
        let wal = path + "-wal"
        if !FileManager.default.fileExists(atPath: wal) {
            try pool.write { _ in }      // make sure the WAL file exists
        }
        let fd = open(wal, O_EVTONLY)
        guard fd >= 0 else { throw DatabaseError(message: "cannot watch \(wal)") }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: queue)
        src.setEventHandler {
            // Coarse: any external write invalidates all observed tables. Fine at personal scale.
            try? pool.write { db in try db.notifyChanges(in: .fullDatabase) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
