import Foundation
import GRDB
import Observation
import GlyCore

/// The item browser's views (item-browser I3): presets, saved views (from the store, written through commands) and tag
/// views, each with the changes the user made while the app runs ("Back to a view"), and the view currently shown.
@MainActor
@Observable
final class BrowserModel {
    private(set) var saved: [ItemView] = []
    /// Changed filter, grouping or sorting per view id, until reset.
    private var edited: [String: ItemView] = [:]
    /// Tag views by id, so a tag view keeps its display name.
    @ObservationIgnored private var tagViews: [String: ItemView] = [:]
    /// The browser view in the main area; nil when it shows something else (Day, an item's page).
    var activeViewID: String?
    @ObservationIgnored private var app: AppModel?
    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var importStarted = false

    /// Observes the saved views and imports, once, views an earlier build kept in `UserDefaults`.
    func attach(_ store: ReadOnlyStore?, app: AppModel) {
        guard let store else { return }
        self.app = app
        observation = store.observe(ValueObservation.tracking { try ViewQueries.list($0) },
                                    onError: { print("views observation: \($0)") },
                                    onChange: { [weak self] in self?.saved = $0 })
        let old = SavedViews.load()
        guard !old.isEmpty, !importStarted else { return }
        importStarted = true
        Task {
            for v in old { _ = await app.send(.createView(ViewDraft(v, name: v.name)), asSystem: true, quiet: true) }
            SavedViews.save([])
        }
    }

    /// The view as defined (preset, saved or tag view), without the user's unsaved changes.
    func base(_ id: String) -> ItemView? {
        ItemView.presets.first { $0.id == id } ?? saved.first { $0.id == id } ?? tagViews[id]
    }

    /// The view as currently shown.
    func view(_ id: String) -> ItemView { edited[id] ?? base(id) ?? .all }

    /// Registers a tag's view and returns its id.
    func tagView(_ name: String) -> String {
        let v = ItemView.tag(name)
        if tagViews[v.id] == nil { tagViews[v.id] = v }
        return v.id
    }

    func update(_ id: String, _ change: (inout ItemView) -> Void) {
        var v = view(id)
        change(&v)
        edited[id] = v == base(id) ? nil : v
    }

    func setQuery(_ id: String, _ query: ItemQuery) { update(id) { $0.query = query } }

    func isModified(_ id: String) -> Bool { edited[id] != nil }

    func reset(_ id: String) { edited[id] = nil }

    // MARK: Saved views (specs/item-browser "Saved views")

    /// Saves the current state of a view under a new name (one undo step); returns the new view's id.
    func saveView(from id: String, name: String) async -> String? {
        var v = view(id)
        guard let app, case .ok(let r) = await app.send(.createView(ViewDraft(v, name: name))), let newID = r.id else { return nil }
        // Shown at once; the observation brings the stored row right after.
        v.id = newID; v.name = name.trimmingCharacters(in: .whitespacesAndNewlines); v.symbol = "line.3.horizontal.decrease.circle"
        if !saved.contains(where: { $0.id == newID }) { saved.append(v) }
        return newID
    }

    /// Writes the current changes into a saved view.
    func updateSaved(_ id: String) {
        guard let current = edited[id] else { return }
        Task {
            guard let app, case .ok = await app.send(.updateView(id: id, ViewPatch(current))) else { return }
            edited[id] = nil
        }
    }

    func rename(_ id: String, to name: String) {
        Task {
            guard let app, case .ok = await app.send(.updateView(id: id, ViewPatch(name: name))) else { return }
            if edited[id] != nil { edited[id]?.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    func delete(_ id: String) {
        edited[id] = nil
        Task { await app?.send(.deleteView(id: id)) }
    }
}
