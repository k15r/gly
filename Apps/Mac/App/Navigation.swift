import AppKit
import SwiftUI
import WorkDashCore

/// Where the main area is, with back/forward history (info-pages-and-links design P9).
@MainActor
@Observable
final class Navigation {
    enum Destination: Hashable {
        case day, tasks, pages
        case page(String)       // page id
        case task(String)       // task id (task page)
        case tag(String)        // tag path (display)
    }

    private(set) var current: Destination = .day
    private var backStack: [Destination] = []
    private var forwardStack: [Destination] = []
    var day = LocalDay(date: Date())

    /// Sheets shown above everything.
    var showQuickOpen = false
    var showNewPage = false

    /// Incremented to ask the visible view to open a new-task editor (⌘N).
    private(set) var newTaskRequest = 0

    private var mouseMonitor: Any?

    init() {
        // Mouse side buttons: 3 = back, 4 = forward (like browsers and Finder).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self else { return event }
            switch event.buttonNumber {
            case 3: self.back(); return nil
            case 4: self.forward(); return nil
            default: return event
            }
        }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func go(_ destination: Destination) {
        guard destination != current else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = destination
    }

    func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        current = previous
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        current = next
    }

    /// ⌘N: a page where pages are shown, otherwise a task.
    func requestNew() {
        switch current {
        case .pages, .page: showNewPage = true
        default: newTaskRequest += 1
        }
    }
}
