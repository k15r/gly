import AppKit
import SwiftUI
import WorkDashCore

/// Owns the capture panel and the global shortcut (quick-capture Q2–Q4).
@MainActor
@Observable
final class CaptureController {
    var text = ""
    var kind: CaptureKind = .task
    private(set) var shortcut = CaptureShortcut.load()
    /// False when the shortcut couldn't be registered (taken by another app or the system).
    private(set) var shortcutAvailable = true

    @ObservationIgnored private var panel: CapturePanel?
    @ObservationIgnored private var app: AppModel?
    @ObservationIgnored private var nav: Navigation?
    @ObservationIgnored private var environment: ((AnyView) -> AnyView)?
    /// Opens the main window when none is open (set by a view that has `openWindow`).
    @ObservationIgnored var openMainWindow: () -> Void = {}

    func start(app: AppModel, nav: Navigation, environment: @escaping (AnyView) -> AnyView) {
        self.app = app; self.nav = nav; self.environment = environment
        GlobalHotKey.shared.action = { [weak self] in self?.toggle() }
        shortcutAvailable = GlobalHotKey.shared.register(shortcut)
    }

    func setShortcut(_ new: CaptureShortcut) {
        shortcut = new
        new.save()
        shortcutAvailable = GlobalHotKey.shared.register(new)
    }

    func toggle() {
        if let panel, panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Upper third of the screen with the mouse, like Spotlight.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.68))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    var draft: CaptureDraft { CaptureParser.parse(text, kind: kind, today: LocalDay(date: Date())) }

    /// Creates the item; with `open`, shows it in WorkDash. The text is only cleared after a successful save.
    func save(open: Bool) {
        let d = draft
        guard !d.isEmpty, let app else { return }
        Task {
            let result = await app.send(d.kind == .task ? .createTask(d.taskDraft) : .createPage(d.pageDraft))
            guard case .ok(let r) = result, let id = r.id else { return }
            text = ""
            close()
            if open {
                NSApp.activate(ignoringOtherApps: true)
                if !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }) { openMainWindow() }
                NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                nav?.editRequest = id      // open in edit mode with the cursor in the text
                nav?.go(d.kind == .task ? .task(id) : .page(id))
            }
        }
    }

    private func makePanel() -> CapturePanel {
        let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 96))
        let view = CaptureView(controller: self)
        panel.contentView = NSHostingView(rootView: environment?(AnyView(view)) ?? AnyView(view))
        return panel
    }
}

/// A floating panel that takes keyboard input without activating WorkDash (Q3).
final class CapturePanel: NSPanel, NSWindowDelegate {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    /// Clicking elsewhere closes it; the typed text stays for next time.
    func windowDidResignKey(_ notification: Notification) { orderOut(nil) }
}
