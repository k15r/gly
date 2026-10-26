import SwiftUI
import WorkDashCore

/// Where the main area is, with back/forward history (info-pages-and-links design P9).
@MainActor
@Observable
final class Navigation {
    enum Destination: Hashable {
        case day, tasks, pages, calendars
        case page(String)       // page id
        case tag(String)        // tag path (display)
    }

    private(set) var current: Destination = .day
    private var backStack: [Destination] = []
    private var forwardStack: [Destination] = []
    var day = LocalDay(date: Date())

    /// Sheets shown above everything.
    var editingTask: TaskEditorTarget?
    var showQuickOpen = false
    var showNewPage = false

    /// Incremented to ask the visible view to open a new-task editor (⌘N).
    private(set) var newTaskRequest = 0

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
