import Foundation
import GRDB
import Observation
import WorkDashCore

/// Live task data for the views, observed from the read-only store (updates on agent writes, design L2).
@MainActor
@Observable
final class TasksModel {
    private(set) var dayTasks: [DayTask] = []
    private(set) var list: [TaskItem] = []
    private(set) var tagTree: [TagNode] = []
    /// What the user's next undo / redo would do (Edit menu titles).
    private(set) var undoLabel: String?
    private(set) var redoLabel: String?
    /// Recent changes made by agents (Settings → Agents).
    private(set) var agentChanges: [AgentChange] = []
    var mode: TaskListMode = .open { didSet { observeList() } }
    var tagFilter: TagName? { didSet { observeList() } }
    /// "Show unused tags" in the tag tree (tag-colors C6); remembered per Mac.
    var showUnusedTags = UserDefaults.standard.bool(forKey: "showUnusedTags") {
        didSet { UserDefaults.standard.set(showUnusedTags, forKey: "showUnusedTags"); observeTags() }
    }

    private(set) var day: LocalDay = LocalDay(date: Date())
    private(set) var today: LocalDay = LocalDay(date: Date())
    private var store: ReadOnlyStore?
    private var dayObservation: AnyDatabaseCancellable?
    private var listObservation: AnyDatabaseCancellable?
    private var tagObservation: AnyDatabaseCancellable?
    private var undoObservation: AnyDatabaseCancellable?
    private var agentObservation: AnyDatabaseCancellable?

    func attach(_ store: ReadOnlyStore?, writer: String) {
        guard let store, self.store !== store else { return }
        self.store = store
        observeDay(); observeList(); observeTags()
        undoObservation = store.observe(ValueObservation.tracking { db in
                                            UndoLabels(undo: try db.undoLabel(writer: writer), redo: try db.redoLabel(writer: writer))
                                        },
                                        onError: { print("undo observation: \($0)") },
                                        onChange: { [weak self] in self?.undoLabel = $0.undo; self?.redoLabel = $0.redo })
        agentObservation = store.observe(ValueObservation.tracking { try AgentActivity.recent($0) },
                                         onError: { print("agent observation: \($0)") },
                                         onChange: { [weak self] in self?.agentChanges = $0 })
    }

    private struct UndoLabels { var undo: String?; var redo: String? }

    func set(day: LocalDay, today: LocalDay) {
        guard day != self.day || today != self.today else { return }
        let todayChanged = today != self.today
        self.day = day
        self.today = today
        observeDay()
        if todayChanged { observeList(); observeTags() }
    }

    func task(id: String) -> TaskItem? {
        try? store?.read { try TaskQueries.task($0, id: id) }
    }

    /// All live tag names (the tag picker's tree).
    func allTagNames() -> [String] {
        (try? store?.read { try TagQueries.list($0, today: LocalDay(date: Date()).description).map(\.name) }) ?? []
    }


    private func observeDay() {
        guard let store else { return }
        let day = self.day, today = self.today
        dayObservation = store.observe(ValueObservation.tracking { try TaskQueries.tasksForDay($0, day: day, today: today) },
                                       onError: { print("day observation: \($0)") },
                                       onChange: { [weak self] in self?.dayTasks = $0 })
    }

    private func observeList() {
        guard let store else { return }
        let mode = self.mode, today = self.today, tag = self.tagFilter
        listObservation = store.observe(ValueObservation.tracking { try TaskQueries.taskList($0, mode: mode, today: today, tag: tag) },
                                        onError: { print("list observation: \($0)") },
                                        onChange: { [weak self] in self?.list = $0 })
    }

    private func observeTags() {
        guard let store else { return }
        let today = self.today.description, unused = showUnusedTags
        tagObservation = store.observe(ValueObservation.tracking { try TagQueries.tagTree($0, today: today, includeUnused: unused) },
                                       onError: { print("tag observation: \($0)") },
                                       onChange: { [weak self] in self?.tagTree = $0 })
    }
}

