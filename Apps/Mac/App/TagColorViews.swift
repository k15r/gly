import AppKit
import GRDB
import SwiftUI
import WorkDashCore

/// Effective tag colors for every view (tag-colors C4): one observation of the tags' own colors; chips just read it.
@MainActor
@Observable
final class TagColorModel {
    private(set) var colors = TagColors()
    @ObservationIgnored private var store: ReadOnlyStore?
    @ObservationIgnored private var observation: AnyDatabaseCancellable?

    func attach(_ store: ReadOnlyStore?) {
        guard let store, self.store !== store else { return }
        self.store = store
        observation = store.observe(ValueObservation.tracking { try TagQueries.colors($0) },
                                    onError: { print("tag colors observation: \($0)") },
                                    onChange: { [weak self] in self?.colors = $0 })
    }

    func color(_ name: String) -> Color { colors.color(name).swiftUI }
}

extension TagColor {
    /// System colors adapt to light and dark mode (C1).
    var swiftUI: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// A colored dot for menu items (menus template-render SF Symbols, so a real image keeps the color).
    var menuImage: Image {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(swiftUI).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }
}

/// "Automatic" plus the palette, the tag's own choice checked (tag tree context menu, tag page header; specs/tags).
struct TagColorMenuItems: View {
    @Environment(AppModel.self) private var app
    @Environment(TagColorModel.self) private var tagColors
    let name: String

    var body: some View {
        let own = tagColors.colors.own[TagName.key(for: name)]
        Toggle("Automatic", isOn: Binding(get: { own == nil }, set: { _ in set(nil) }))
        Divider()
        ForEach(TagColor.allCases, id: \.self) { color in
            Toggle(isOn: Binding(get: { own == color }, set: { _ in set(color) })) {
                Label { Text(color.label) } icon: { color.menuImage }
            }
        }
    }

    private func set(_ color: TagColor?) {
        Task { await app.send(.setTagColor(name: name, color: color)) }
    }
}

/// The tag page header's color picker: a small square in the effective color; where it comes from is in the tooltip.
struct TagColorControl: View {
    @Environment(AppModel.self) private var app
    @Environment(TagColorModel.self) private var tagColors
    let name: String

    var body: some View {
        let effective = tagColors.colors.effective(name)
        Menu {
            TagColorMenuItems(name: name)
        } label: {
            RoundedRectangle(cornerRadius: 3).fill(effective.color.swiftUI).frame(width: 14, height: 14)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(!app.canWrite)
        .help("Tag color: \(Self.caption(effective.source))")
    }

    static func caption(_ source: TagColorSource) -> String {
        switch source {
        case .own: "own color"
        case .inherited(let from): "inherited from \(from)"
        case .automatic: "automatic"
        }
    }
}

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
