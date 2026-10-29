import AppKit
import SwiftUI
import GlyCore

/// A meeting page: stored notes (from search, tags, backlinks) or an appointment from the day view (notes or not).
enum MeetingRef: Hashable {
    case notes(String)
    case appointment(Appointment)
}

/// Where the main area is, with back/forward history (info-pages-and-links design P9).
@MainActor
@Observable
final class Navigation {
    enum Destination: Hashable {
        case day, trash
        case page(String)       // page id
        case task(String)       // task id (task page)
        case tag(String)        // tag path (display)
        case meeting(MeetingRef)    // meeting-pages N7
        case bookmark(String)       // bookmark id (bookmark page)
        case items(String)          // item browser view id (item-browser I3)
    }

    private(set) var current: Destination = .day
    private var backStack: [Destination] = []
    private var forwardStack: [Destination] = []
    var day = LocalDay(date: Date())

    /// An item to open with the cursor in its text (⌘Return in quick capture), live-preview L5.
    var editRequest: String?

    /// Sheets shown above everything.
    var showQuickOpen = false
    var showNewPage = false
    /// Tags for the next new page (the browser view's tag filters).
    var newPageTags: [String] = []

    /// Incremented to ask the visible view to open a new-task editor (⌘N).
    private(set) var newTaskRequest = 0

    private var mouseMonitor: Any?

    init() {
        // Mouse side buttons: 3 = back, 4 = forward (like browsers and Finder). Drivers such as
        // Logi Options+ send a horizontal swipe instead; a swipe right means back, as in Safari.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .otherMouseDown where event.buttonNumber == 3: self.back(); return nil
            case .otherMouseDown where event.buttonNumber == 4: self.forward(); return nil
            case .swipe where event.deltaX > 0: self.back(); return nil
            case .swipe where event.deltaX < 0: self.forward(); return nil
            default: return event
            }
        }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// The Trash entry to select when the Trash opens (from a broken link's "Show in Trash").
    var trashSelection: String?

    func showTrash(selecting id: String?) {
        trashSelection = id
        go(.trash)
    }

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
        case .page, .items(ItemView.pages.id): showNewPage = true
        default: newTaskRequest += 1
        }
    }
}
