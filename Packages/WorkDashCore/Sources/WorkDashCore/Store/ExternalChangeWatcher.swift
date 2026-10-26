import Foundation
import GRDB

/// Makes `ValueObservation` notice writes from other processes (foundation-spikes D3/S4).
///
/// GRDB only observes writes made through its own connections. The agent writes in another
/// process, so the app watches the database's `-wal` file and tells GRDB that the database changed.
public final class ExternalChangeWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "dev.k15r.workdash.external-change-watcher")

    /// - Parameter path: path of the database file (the `-wal` file next to it is watched).
    public init(pool: DatabasePool, path: String) throws {
        let wal = path + "-wal"
        guard FileManager.default.fileExists(atPath: wal) else {
            throw StoreError.databaseMissing(wal)
        }
        let fd = open(wal, O_EVTONLY)
        guard fd >= 0 else { throw StoreError.databaseMissing(wal) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: queue)
        source.setEventHandler {
            // Coarse but cheap at personal scale: every external write re-evaluates all observations.
            // Requires a connection GRDB considers writable: notifyChanges is a no-op on
            // `Configuration.readonly` pools (see StoreFactory.openReadOnly).
            try? pool.write { db in try db.notifyChanges(in: .fullDatabase) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}

/// The app's view of the database (design L2): reading and observing only.
///
/// The app never writes; all writes go to the agent over XPC. That is enforced by this type
/// exposing no write API. (A `Configuration.readonly` pool can't be used: GRDB skips
/// `notifyChanges` on read-only connections, which would break `ExternalChangeWatcher`.
/// `PRAGMA query_only` doesn't stick either: GRDB resets it on the writer connection.)
public final class ReadOnlyStore {
    private let pool: DatabasePool
    private var watcher: ExternalChangeWatcher?
    public let url: URL

    /// Opens the existing database (created and migrated by the agent) and starts watching it.
    public init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreError.databaseMissing(url.path) }
        self.url = url
        pool = try DatabasePool(path: url.path)
        watcher = try ExternalChangeWatcher(pool: pool, path: url.path)
    }

    public func read<T>(_ body: (Database) throws -> T) throws -> T {
        try pool.read(body)
    }

    /// Starts an observation that also fires for writes made by other processes.
    public func observe<Reducer>(
        _ observation: ValueObservation<Reducer>,
        scheduling scheduler: some ValueObservationScheduler = .async(onQueue: .main),
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void
    ) -> AnyDatabaseCancellable {
        observation.start(in: pool, scheduling: scheduler, onError: onError, onChange: onChange)
    }
}
