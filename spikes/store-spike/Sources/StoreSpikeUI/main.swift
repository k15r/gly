// Spike 2 (foundation-spikes), task 3.8: SwiftUI list bound to a tag filter via ValueObservation. Throwaway code.
// Usage: StoreSpikeUI <db-path> [filter]   e.g. StoreSpikeUI /tmp/wd.sqlite "person/*"
import AppKit
import Combine
import Foundation
import GRDB
import StoreSpike
import SwiftUI

let args = CommandLine.arguments
let dbPath = args.count > 1 ? args[1] : NSTemporaryDirectory() + "wd-ui.sqlite"
let filter = args.count > 2 ? args[2] : "person/*"

func log(_ s: String) { print(s); fflush(stdout) }

struct ItemRow: Identifiable, Equatable { let id, title, kind: String }

final class Model: ObservableObject {
    @Published var rows: [ItemRow] = []
    @Published var error: String?
    private var cancellable: AnyDatabaseCancellable?
    private var watcher: ExternalChangeWatcher?
    let pool: DatabasePool

    init() {
        pool = try! DatabasePool(path: dbPath)
        try! Schema.migrator.migrate(pool)
        let empty = try! pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM items")! } == 0
        if empty {
            try! pool.write { _ = try $0.generate() }
            log("generated fixture into \(dbPath)")
        }
        watcher = try! ExternalChangeWatcher(pool: pool, path: dbPath)
        let observation = ValueObservation.tracking { db -> [ItemRow] in
            try db.query(filter).prefix(500).map { ItemRow(id: $0["id"], title: $0["title"], kind: $0["kind"]) }
        }
        cancellable = observation.start(in: pool, scheduling: .mainActor, onError: { [weak self] e in
            self?.error = "\(e)"
            log("ERROR \(e)")
        }, onChange: { [weak self] rows in
            self?.rows = rows
            log("UPDATE \(rows.count) rows; first: \(rows.first?.title ?? "-")")
        })
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading) {
            Text("Filter: \(filter)  —  \(model.rows.count) items (max 500)").font(.headline).padding(.horizontal)
            if let e = model.error { Text(e).foregroundStyle(.red).padding(.horizontal) }
            List(model.rows) { r in
                HStack { Text(r.kind).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading); Text(r.title) }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = Model()
    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "WorkDash store spike"
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        log("WINDOW shown, db \(dbPath), filter \(filter)")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
