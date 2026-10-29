import SwiftUI
import GlyCore

struct TaskDetail: Equatable {
    var task: TaskItem?
    var backlinks: [Backlink]
    /// Recorded work per day and kind, newest first (task-progress P5).
    var work: [WorkEntry] = []
}

/// A task in the main area, laid out like a page (specs/tasks "Task page"): title, field row, notes, backlinks.
/// Every change is saved at once; each field change and each notes edit session is one undo step.
struct TaskPageView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    @Environment(Clock.self) private var clock
    @Environment(PlanningModel.self) private var planning
    let id: String

    @State private var live = Live<TaskDetail>()
    @State private var title = ""
    @State private var tags: [String] = []
    @State private var pendingTag = ""
    /// Opened for writing (quick capture ⌘Return): the cursor goes into the notes (live-preview L5).
    @State private var focusText = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if let detail = live.value, let task = detail.task {
                content(task, backlinks: detail.backlinks, work: detail.work)
            } else if live.loaded {
                ContentUnavailableView("Task not found", systemImage: "checkmark.circle.badge.questionmark",
                                       description: Text("It may have been deleted."))
            } else {
                ProgressView()
            }
        }
        .task(id: id) {
            let id = self.id
            live.observe(wiki.store) { db in
                TaskDetail(task: try TaskQueries.task(db, id: id), backlinks: try LinkQueries.backlinks(db, to: id),
                           work: try TaskQueries.work(db, taskID: id))
            }
        }
        .onChange(of: live.value?.task) { _, task in
            guard let task else { return }
            if !titleFocused { title = task.title }
            tags = task.tags
            if nav.editRequest == task.id { focusText = true; nav.editRequest = nil }
        }
    }

    private func content(_ task: TaskItem, backlinks: [Backlink], work: [WorkEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    send(.setStatus(id: task.id, task.status == .done ? .open : .done))
                } label: {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle").font(.title2)
                }
                .buttonStyle(.plain).help(task.status == .done ? "Reopen" : "Complete")
                TextField("Title", text: $title).font(.title.bold()).textFieldStyle(.plain)
                    .strikethrough(task.status == .done || task.status == .dropped)
                    .focused($titleFocused)
                    .onSubmit { saveTitle(task) }
                    .onChange(of: titleFocused) { _, focused in if !focused { saveTitle(task) } }
                    .onDisappear { saveTitle(task) }          // leaving while editing: the edit belongs to this task
                Spacer()
                Menu {
                    TaskActions(task: task, onEdit: nil)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding([.horizontal, .top])

            TaskPropertyRow(task: task, tags: $tags, pendingTag: $pendingTag).padding(.horizontal).padding(.top, 8)
                .onChange(of: tags) { _, new in
                    guard new != task.tags else { return }
                    send(.updateTask(id: task.id, TaskPatch(tags: new)))
                }
            if task.effort != nil || task.hasEstimatedParts { TaskProgressRow(task: task, work: work).padding(.horizontal).padding(.top, 6) }
            if allPartsDone(task) {
                // specs/tasks "All parts done": offered, never automatic.
                HStack {
                    Label("All parts done", systemImage: "checkmark.seal").foregroundStyle(.green)
                    Button("Complete task") { send(.setStatus(id: task.id, .done)) }.disabled(!app.canWrite)
                }
                .font(.callout).padding(.horizontal).padding(.top, 6)
            }
            Divider().padding(.top, 8)

            // One mode: the notes in the live-preview editor (specs/markdown-editing "Same editor everywhere").
            GlyMarkdownEditor(text: task.body, onCommit: { text, session in
                send(.updateTask(id: task.id, TaskPatch(body: text, session: session)))
            }, initialCaret: focusText ? (task.body as NSString).length : nil)
            .frame(maxHeight: .infinity)
            Divider()
            BacklinksView(backlinks: backlinks).padding().frame(maxHeight: 180, alignment: .top)
        }
    }

    private func allPartsDone(_ task: TaskItem) -> Bool {
        let parts = task.parts
        return task.status == .open && !parts.isEmpty && parts.allSatisfy(\.done)
    }

    private func saveTitle(_ task: TaskItem) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { title = task.title; return }
        guard trimmed != task.title else { return }
        send(.updateTask(id: task.id, TaskPatch(title: trimmed)))
    }

    private func send(_ command: Command) { Task { await app.send(command) } }
}

/// Remaining effort and recorded work of a task, with "Set remaining…" and "Reset" (specs/tasks "Progress on the task page").
struct TaskProgressRow: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    let task: TaskItem
    let work: [WorkEntry]
    @State private var editing = false

    var body: some View {
        let dayLength = planning.hours.minutesPerDay
        let effortMinutes = task.effort.map { planning.sizes[$0] } ?? 0
        let left = task.remaining(sizes: planning.sizes, dayMinutes: planning.hours.minutesPerDay) ?? 0
        if task.hasEstimatedParts {
            // Estimated checklist items drive what's left; recording work and setting it by hand don't apply (subtasks S2).
            let parts = task.parts
            let unestimated = parts.filter { !$0.done && $0.estimate == nil }.count
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Progress").foregroundStyle(.secondary)
                Text("\(formatEffort(Double(left), dayLength: dayLength)) left from \(parts.filter(\.done).count)/\(parts.count) parts").monospacedDigit()
                if unestimated > 0 { Text("\(unestimated) without estimate").font(.caption).foregroundStyle(.secondary) }
                if let effort = task.effort { Text("task estimate \(effort.label)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
        } else {
            manualProgress(left: left, effortMinutes: effortMinutes, dayLength: dayLength)
        }
    }

    private func manualProgress(left: Int, effortMinutes: Int, dayLength: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Progress").foregroundStyle(.secondary)
            Text(work.isEmpty ? "nothing recorded" : "\(formatEffort(Double(left), dayLength: dayLength)) of \(task.effort?.label ?? "") left")
                .monospacedDigit()
            if !work.isEmpty {
                Text(work.map { entry in Self.describe(entry, dayLength: dayLength) }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Set remaining…") { editing = true }
                .buttonStyle(.borderless).disabled(!app.canWrite)
                .popover(isPresented: $editing, arrowEdge: .bottom) {
                    RemainingEditor(task: task) { editing = false }.padding().frame(width: 240)
                }
            if !work.isEmpty {
                Button("Reset") { Task { await app.send(.resetRemaining(id: task.id)) } }
                    .buttonStyle(.borderless).disabled(!app.canWrite)
                    .help("Back to the full effort (undo brings the recorded work back)")
            }
        }
    }

    /// "Tue 1d", "Wed +2h left (adjusted)" for negative adjustments, "by an agent" for agent records.
    static func describe(_ entry: WorkEntry, dayLength: Int) -> String {
        let day = LocalDay(entry.day).map(DayView.weekday) ?? entry.day
        let amount = formatEffort(Double(abs(entry.minutes)), dayLength: dayLength)
        switch entry.kind {
        case .adjust: return entry.minutes < 0 ? "\(day) +\(amount) left (adjusted)" : "\(day) \(amount) (adjusted)"
        case .agent: return "\(day) \(entry.minutes < 0 ? "−" : "")\(amount) by an agent"
        case .part: return "\(day) \(amount)"
        }
    }
}

/// Sets what's left of a task's effort, in 30-minute steps (task-progress P5; also in the effort chip's popover).
struct RemainingEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    let task: TaskItem
    let onDone: () -> Void
    @State private var draft = 0

    var body: some View {
        let dayLength = planning.hours.minutesPerDay
        let effortMinutes = task.effort.map { planning.sizes[$0] } ?? 0
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: $draft, in: 0...max(effortMinutes * 2, 60), step: 30) {
                // Fixed width, so the arrows stay put while the text grows ("7h" → "7h 30m").
                Text("\(formatEffort(Double(draft), dayLength: dayLength)) left").monospacedDigit()
                    .frame(width: 130, alignment: .leading)
            }
            HStack {
                Button("Cancel", action: onDone)
                Spacer()
                Button("Set") {
                    let day = LocalDay(date: Date()).description
                    Task { await app.send(.setRemaining(id: task.id, minutes: draft, effortMinutes: effortMinutes, day: day)) }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!app.canWrite)
            }
        }
        .onAppear { draft = task.remaining(sizes: planning.sizes, dayMinutes: dayLength) ?? effortMinutes }
    }
}
