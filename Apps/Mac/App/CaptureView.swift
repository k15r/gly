import SwiftUI
import GlyCore

/// The capture panel's content (specs/quick-capture "Capture panel").
struct CaptureView: View {
    @Bindable var controller: CaptureController
    @FocusState private var focused: Bool

    var body: some View {
        let draft = controller.draft
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
                TextField(placeholder, text: $controller.text)
                    .textFieldStyle(.plain).font(.title2)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        controller.save(open: press.modifiers.contains(.command))
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        controller.kind = controller.kind.next
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        controller.close()
                        return .handled
                    }
            }
            HStack {
                Text(controller.text.isEmpty ? controller.kind.label : preview(draft))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("Tab: \(controller.kind.next.label)   ↩ save   ⌘↩ save & open   esc")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 560)
        .background(.regularMaterial)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
    }

    private var symbol: String {
        switch controller.kind { case .task: "circle"; case .page: "doc.text"; case .bookmark: "bookmark" }
    }

    private var placeholder: String {
        switch controller.kind {
        case .task: "New task – #tag, tomorrow, fri, 3 Nov, !"
        case .page: "New page – #tag"
        case .bookmark: "New bookmark – URL, title, #tag"
        }
    }

    private func preview(_ draft: CaptureDraft) -> String {
        let url = draft.url ?? ""
        return draft.preview(today: LocalDay(date: Date()), fetchedTitle: controller.fetchedTitles[url], fetching: controller.fetching.contains(url))
    }
}
