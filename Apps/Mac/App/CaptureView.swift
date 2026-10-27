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
                Image(systemName: controller.kind == .task ? "circle" : "doc.text").font(.title2).foregroundStyle(.secondary)
                TextField(controller.kind == .task ? "New task – #tag, tomorrow, fri, 3 Nov, !" : "New page – #tag",
                          text: $controller.text)
                    .textFieldStyle(.plain).font(.title2)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        controller.save(open: press.modifiers.contains(.command))
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        controller.kind = controller.kind == .task ? .page : .task
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        controller.close()
                        return .handled
                    }
            }
            HStack {
                Text(draft.isEmpty && controller.text.isEmpty ? (controller.kind == .task ? "Task" : "Page") : draft.preview(today: LocalDay(date: Date())))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("Tab: \(controller.kind == .task ? "Page" : "Task")   ↩ save   ⌘↩ save & open   esc")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 560)
        .background(.regularMaterial)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
    }
}
