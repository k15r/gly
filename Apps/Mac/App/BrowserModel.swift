import Foundation
import Observation
import GlyCore

/// The item browser's views (item-browser I3): presets, saved views (per Mac) and tag views, each with the changes
/// the user made while the app runs ("Back to a view"), and the view currently shown (for the tag tree).
@MainActor
@Observable
final class BrowserModel {
    private(set) var saved: [ItemView] = SavedViews.load()
    /// Changed filter, grouping or sorting per view id, until reset.
    private var edited: [String: ItemView] = [:]
    /// Tag views by id, so a tag view keeps its display name.
    @ObservationIgnored private var tagViews: [String: ItemView] = [:]
    /// The browser view in the main area; nil when it shows something else (Day, an item's page).
    var activeViewID: String?

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

    /// Saves the current state of a view under a new name; returns the new view's id.
    func saveView(from id: String, name: String) -> String {
        var v = view(id)
        v.id = "saved:" + UUID().uuidString
        v.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        v.symbol = "line.3.horizontal.decrease.circle"
        saved.append(v)
        SavedViews.save(saved)
        return v.id
    }

    /// Writes the current changes into a saved view.
    func updateSaved(_ id: String) {
        guard let i = saved.firstIndex(where: { $0.id == id }), let current = edited[id] else { return }
        saved[i] = current
        edited[id] = nil
        SavedViews.save(saved)
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[i].name = trimmed
        if edited[id] != nil { edited[id]?.name = trimmed }
        SavedViews.save(saved)
    }

    func delete(_ id: String) {
        saved.removeAll { $0.id == id }
        edited[id] = nil
        SavedViews.save(saved)
    }
}
