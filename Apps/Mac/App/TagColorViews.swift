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

/// The tag page header's color control: a dot with the menu, and where the color comes from.
struct TagColorControl: View {
    @Environment(AppModel.self) private var app
    @Environment(TagColorModel.self) private var tagColors
    let name: String

    var body: some View {
        let effective = tagColors.colors.effective(name)
        Menu {
            TagColorMenuItems(name: name)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(effective.color.swiftUI).frame(width: 12, height: 12)
                Text(Self.caption(effective.source)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(!app.canWrite)
        .help("Tag color")
    }

    static func caption(_ source: TagColorSource) -> String {
        switch source {
        case .own: "own color"
        case .inherited(let from): "inherited from \(from)"
        case .automatic: "automatic"
        }
    }
}
