import AppKit
import SwiftUI
import GlyCore

/// Owns the capture panel and the global shortcut (quick-capture Q2–Q4).
@MainActor
@Observable
final class CaptureController {
    var text = "" { didSet { fetchTitleIfNeeded() } }
    var kind: CaptureKind = .task { didSet { fetchTitleIfNeeded() } }
    /// Page titles fetched for typed bookmark URLs (bookmarks B6), and the fetches in flight.
    private(set) var fetchedTitles: [String: String] = [:]
    private(set) var fetching: Set<String> = []
    @ObservationIgnored private var fetches: [String: Task<String?, Never>] = [:]
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

    /// Starts fetching the page title of a typed bookmark URL that has no typed title yet.
    private func fetchTitleIfNeeded() {
        let d = draft
        guard d.kind == .bookmark, d.title.isEmpty, let url = d.url, fetches[url] == nil, let link = URL(string: url),
              ["http", "https"].contains(link.scheme ?? "") else { return }
        fetching.insert(url)
        fetches[url] = Task { [weak self] in
            let title = await Self.pageTitle(link)
            self?.fetching.remove(url)
            if let title { self?.fetchedTitles[url] = title }
            return title
        }
    }

    /// The `<title>` from the first 64 KB of a page, within 5 s; nil on any failure (the host is the fallback).
    nonisolated static func pageTitle(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
                var data = Data()
                do {
                    for try await byte in bytes {
                        data.append(byte)
                        if data.count >= PageTitle.maxBytes { break }
                        if data.count % 4096 == 0, let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                           s.range(of: "</title>", options: .caseInsensitive) != nil { break }
                    }
                } catch {}
                let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                return PageTitle.extract(html: html)
            }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// The command for a draft; a bookmark without a typed title waits for its page title (at most the fetch's 5 s).
    private func command(for d: CaptureDraft) async -> Command {
        switch d.kind {
        case .task: return .createTask(d.taskDraft)
        case .page: return .createPage(d.pageDraft)
        case .bookmark:
            var title = d.url.flatMap { fetchedTitles[$0] }
            if title == nil, d.title.isEmpty, let url = d.url, let fetch = fetches[url] { title = await fetch.value }
            return .createBookmark(d.bookmarkDraft(fetchedTitle: title))
        }
    }

    /// Creates the item; with `open`, shows it in gly. The text is only cleared after a successful save.
    func save(open: Bool) {
        let d = draft
        guard !d.isEmpty, let app else { return }
        if d.kind == .bookmark && !open { close() }      // the title may still be loading: don't hold the panel
        Task {
            let result = await app.send(await command(for: d))
            guard case .ok(let r) = result, let id = r.id else { if d.kind == .bookmark && !open { show() }; return }
            text = ""
            fetchedTitles = [:]; fetches = [:]
            close()
            if open {
                NSApp.activate(ignoringOtherApps: true)
                if !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }) { openMainWindow() }
                NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                switch d.kind {
                case .task, .page:
                    nav?.editRequest = id      // open with the cursor in the text
                    nav?.go(d.kind == .task ? .task(id) : .page(id))
                case .bookmark:
                    nav?.bookmarkEditRequest = id      // the bookmark editor instead of a page (B6)
                    nav?.go(.bookmarks)
                }
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

/// A floating panel that takes keyboard input without activating gly (Q3).
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
