import GRDB
import SwiftUI
import GlyCore
import GlyEditor

/// A sidebar row with a live count from the store (Tasks: open, Pages: all, Trash: deleted in the last 30 days).
struct SidebarCountRow: View {
    @Environment(AppModel.self) private var app
    let title: String
    let symbol: String
    let count: @Sendable (Database) throws -> Int
    @State private var live = Live<Int>()

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let n = live.value, n > 0 { Text("\(n)").foregroundStyle(.secondary).monospacedDigit() }
        }
        // The sidebar appears before the store is open: start (again) once it is.
        .task(id: app.store.map(ObjectIdentifier.init)) { [count] in live.observe(app.store) { try count($0) } }
    }

    /// Items of a browser view.
    nonisolated static func matching(_ query: ItemQuery) -> @Sendable (Database) throws -> Int {
        { @Sendable db in try BrowseQueries.count(db, query) }
    }
    static let openTasks: @Sendable (Database) throws -> Int = { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items WHERE kind = 'task' AND status IN ('open', 'snoozed')") ?? 0
    }
    static let pages: @Sendable (Database) throws -> Int = { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM live_items WHERE kind = 'info'") ?? 0
    }
    static let bookmarks: @Sendable (Database) throws -> Int = { db in try BookmarkQueries.count(db) }
    static let recentlyDeleted: @Sendable (Database) throws -> Int = { db in
        let cutoff = Date().addingTimeInterval(-Double(TrashQueries.defaultDays) * 86400)
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items WHERE kind IN ('info', 'task', 'bookmark') AND deleted_at >= ?", arguments: [cutoff]) ?? 0
    }
}

private struct TrashTaskKey: Equatable { let store: ObjectIdentifier?; let showOlder: Bool }

struct TrashData: Equatable {
    var entries: [TrashEntry]
    var older: Int
}

/// Deleted pages and tasks with a read-only preview and Restore (specs/trash).
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    @State private var live = Live<TrashData>()
    @State private var showOlder = false
    @State private var selection: String?

    var body: some View {
        // A plain HStack, not HSplitView: the nested AppKit split reported its own width to the window's split view,
        // which then slid the sidebar out of the window.
        HStack(spacing: 0) {
            list.frame(width: 300)
            Divider()
            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Trash")
        .task(id: TrashTaskKey(store: app.store.map(ObjectIdentifier.init), showOlder: showOlder)) {
            if let id = nav.trashSelection { selection = id; nav.trashSelection = nil }
            let cutoff = Date().addingTimeInterval(-Double(TrashQueries.defaultDays) * 86400)
            let all = showOlder
            live.observe(app.store) { db in
                TrashData(entries: try TrashQueries.list(db, since: all ? nil : cutoff), older: all ? 0 : try TrashQueries.count(db, before: cutoff))
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            if let data = live.value {
                if data.entries.isEmpty { Text("The trash is empty.").foregroundStyle(.secondary) }
                ForEach(data.entries) { e in
                    row(e).tag(e.id)
                        .contextMenu { Button("Restore") { restore(e) }.disabled(!app.canWrite) }
                }
                if data.older > 0 {
                    Button("Show older (\(data.older))") { showOlder = true }.buttonStyle(.link)
                }
            }
        }
    }

    private func row(_ e: TrashEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(e.title, systemImage: e.kind.linkSymbol).fontWeight(.medium).lineLimit(1)
            if !e.excerpt.isEmpty { Text(e.excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Text(([e.tags.isEmpty ? nil : e.tags.joined(separator: ", ")] + [deletedLine(e)]).compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func deletedLine(_ e: TrashEntry) -> String {
        "deleted " + RelativeDateTimeFormatter().localizedString(for: e.deletedAt, relativeTo: Date()) + " by " + WriterName.display(e.deletedBy)
    }

    @ViewBuilder private var preview: some View {
        if let id = selection, let e = live.value?.entries.first(where: { $0.id == id }),
           let body = try? wiki.store?.read({ try String.fetchOne($0, sql: "SELECT body FROM items WHERE id = ?", arguments: [id]) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(e.title, systemImage: e.kind.linkSymbol).font(.title.bold())
                        Spacer()
                        Button { restore(e) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }.disabled(!app.canWrite)
                    }
                    if !e.tags.isEmpty { HStack(spacing: 4) { ForEach(e.tags, id: \.self) { TagChip(name: $0) } } }
                    Text(deletedLine(e)).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    GlyMarkdownReadView(text: body)          // no onChange: read-only
                }
                .padding()
            }
        } else {
            Text("Select a deleted page or task").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func restore(_ e: TrashEntry) {
        Task {
            guard case .ok = await app.send(.restore(id: e.id)) else { return }
            if selection == e.id { selection = nil }
        }
    }
}
