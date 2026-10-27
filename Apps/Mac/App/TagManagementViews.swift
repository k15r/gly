import SwiftUI
import GlyCore

/// Rename (with merge on conflict) and delete for one tag, shared by the tag tree and the tag page (tag-colors C9).
struct TagManagementPrompts: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    let name: String
    @Binding var renaming: Bool
    @Binding var deleting: Bool
    @State private var newName = ""
    @State private var mergeMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("Rename tag “\(name)”", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Rename") { rename(merge: false) }.keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Subtags are renamed along. Use / for levels.") }
            .onChange(of: renaming) { _, open in if open { newName = name } }
            .alert("Merge tags?", isPresented: Binding(get: { mergeMessage != nil }, set: { if !$0 { mergeMessage = nil } })) {
                Button("Merge") { rename(merge: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(mergeMessage ?? "") Items, descriptions and links of “\(name)” move to the existing tags.")
            }
            .alert(deleteTitle, isPresented: $deleting) {
                Button(usage > 0 ? "Remove from \(usage) item\(usage == 1 ? "" : "s")" : "Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Subtags stay. Undo brings it back.") }
    }

    private var usage: Int { (try? wiki.store?.read { try TagQueries.usage($0, name: name) }) ?? 0 }
    private var deleteTitle: String { usage > 0 ? "Remove “\(name)” from \(usage) item\(usage == 1 ? "" : "s")?" : "Delete unused tag “\(name)”?" }

    private func rename(merge: Bool) {
        let target = newName.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, target != name || merge else { return }
        Task {
            switch await app.send(.renameTag(from: name, to: target, merge: merge), quiet: true) {
            case .ok:
                mergeMessage = nil
                follow(to: target)
            case .failure(let f) where f.code == .conflict:
                mergeMessage = f.message + "."
            case .failure(let f):
                app.lastError = f.message
            }
        }
    }

    /// A visible tag page of the renamed tag (or a subtag) follows the rename.
    private func follow(to target: String) {
        guard case .tag(let current) = nav.current else { return }
        let old = TagName.key(for: name), cur = TagName.key(for: current)
        if cur == old { nav.go(.tag(target)) }
        else if cur.hasPrefix(old + "/") { nav.go(.tag(target + current.dropFirst(name.count))) }
    }

    private func delete() {
        Task {
            guard case .ok = await app.send(.deleteTag(name: name)) else { return }
            if case .tag(let current) = nav.current, TagName.key(for: current) == TagName.key(for: name) { nav.back() }
        }
    }
}
