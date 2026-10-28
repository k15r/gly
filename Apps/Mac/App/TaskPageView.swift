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
    @State private var editing: Bool?
    /// Opened for editing (quick capture ⌘Return): edit mode, cursor in the text.
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
            editing = nil
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
            if nav.editRequest == task.id { editing = true; focusText = true; nav.editRequest = nil }
            if editing == nil { editing = task.body.isEmpty }
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
                Picker("", selection: Binding(get: { editing ?? false }, set: { editing = $0 })) {
                    Text("Read").tag(false)
                    Text("Edit").tag(true)
                }
                .pickerStyle(.segmented).fixedSize()
                .help("Switch between reading and editing the notes (⌘E)")
                Button("") { editing = !(editing ?? false) }.keyboardShortcut("e").hidden().frame(width: 0)
                Menu {
                    TaskActions(task: task, onEdit: nil)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding([.horizontal, .top])

            fields(task).padding(.horizontal).padding(.top, 8)
            if task.effort != nil || task.hasEstimatedParts { TaskProgressRow(task: task, work: work).padding(.horizontal).padding(.top, 6) }
            TaskPartsSection(task: task).padding(.horizontal).padding(.top, 6)
            Form { TagField(tags: $tags, input: $pendingTag) }
                .formStyle(.columns).padding(.horizontal)
                .onChange(of: tags) { _, new in
                    guard new != task.tags else { return }
                    send(.updateTask(id: task.id, TaskPatch(tags: new)))
                }
            Divider().padding(.top, 8)

            if editing == true {
                GlyMarkdownEditor(text: task.body, onCommit: { text, session in
                    send(.updateTask(id: task.id, TaskPatch(body: text, session: session)))
                }, initialCaret: focusText ? (task.body as NSString).length : nil)
                .frame(maxHeight: .infinity)
                Divider()
                BacklinksView(backlinks: backlinks).padding().frame(maxHeight: 180, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if task.body.isEmpty {
                            Text("No notes – switch to Edit (⌘E) to write.").foregroundStyle(.secondary)
                        } else {
                            GlyMarkdownReadView(text: task.body) { new in
                                send(.updateTask(id: task.id, TaskPatch(body: new)))
                            }
                        }
                        Divider()
                        BacklinksView(backlinks: backlinks)
                    }
                    .padding()
                }
            }
        }
    }

    /// Priority, due date, status/snooze, each saved on change.
    private func fields(_ task: TaskItem) -> some View {
        // Wraps onto a second line when the window is narrow; every group keeps its natural width.
        FlowLayout(spacing: 16) {
            Picker("Priority", selection: Binding(get: { task.priority }, set: { p in
                send(.updateTask(id: task.id, TaskPatch(priority: p)))
            })) {
                ForEach(Priority.allCases.reversed(), id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()

            Picker("Effort", selection: Binding(get: { task.effort }, set: { e in
                send(.updateTask(id: task.id, TaskPatch(effort: .some(e))))
            })) {
                Text("–").tag(Effort?.none)
                ForEach(Effort.allCases, id: \.self) { Text($0.label).tag(Effort?.some($0)) }
            }
            .fixedSize()
            .help("How much work this is (sizes in Settings → Planning)")

            dueControl(task)

            Picker("Status", selection: Binding(get: { task.status }, set: { status in
                let snooze = status == .snoozed ? LocalDay(date: Date()).adding(days: 1).description : nil
                send(.setStatus(id: task.id, status, snoozedUntil: snooze))
            })) {
                Text("Open").tag(TaskStatus.open)
                Text("Snoozed").tag(TaskStatus.snoozed)
                Text("Done").tag(TaskStatus.done)
                Text("Dropped").tag(TaskStatus.dropped)
            }
            .fixedSize()
            if task.status == .snoozed, let until = task.snoozedUntil.flatMap(LocalDay.init) {
                DatePicker("until", selection: Binding(get: { until.interval().start }, set: { date in
                    send(.setStatus(id: task.id, .snoozed, snoozedUntil: LocalDay(date: date).description))
                }), displayedComponents: [.date])
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Add due date", or `Due [date] [time / Add time] ✕`.
    @ViewBuilder
    private func dueControl(_ task: TaskItem) -> some View {
        if let due = task.due {
            HStack(spacing: 6) {
                Text("Due").foregroundStyle(.secondary).fixedSize()
                DatePicker("Due", selection: Binding(get: { due.date() ?? Date() }, set: { date in
                    send(.updateTask(id: task.id, TaskPatch(due: .some(Due(date: date, includeTime: due.time != nil)))))
                }), displayedComponents: due.time == nil ? [.date] : [.date, .hourAndMinute])
                .labelsHidden().fixedSize()
                if due.time == nil {
                    Button("Add time") {
                        let start = due.date() ?? Date()
                        send(.updateTask(id: task.id, TaskPatch(due: .some(Due(date: start.addingTimeInterval(9 * 3600), includeTime: true)))))
                    }
                    .buttonStyle(.borderless).fixedSize()
                } else {
                    Button("Remove time") {
                        send(.updateTask(id: task.id, TaskPatch(due: .some(Due(day: due.day)))))
                    }
                    .buttonStyle(.borderless).fixedSize()
                }
                Button { send(.updateTask(id: task.id, TaskPatch(due: .some(nil)))) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove due date")
            }
        } else {
            Button { send(.updateTask(id: task.id, TaskPatch(due: .some(Due(day: clock.today.description))))) } label: {
                Label("Add due date", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderless).fixedSize()
        }
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
    @State private var draft = 0

    var body: some View {
        let dayLength = planning.hours.minutesPerDay
        let effortMinutes = task.effort.map { planning.sizes[$0] } ?? 0
        let left = task.remaining(sizes: planning.sizes) ?? 0
        if task.hasEstimatedParts {
            // Estimated parts drive what's left; recording work and setting it by hand don't apply (subtasks S2).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Progress").foregroundStyle(.secondary)
                Text("\(formatEffort(Double(left), dayLength: dayLength)) left from parts").monospacedDigit()
                if let effort = task.effort { Text("(task estimate \(effort.label))").font(.caption).foregroundStyle(.secondary) }
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
            Button("Set remaining…") { draft = left; editing = true }
                .buttonStyle(.borderless).disabled(!app.canWrite)
                .popover(isPresented: $editing, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(value: $draft, in: 0...max(effortMinutes * 2, 60), step: 30) {
                            // Fixed width, so the arrows stay put while the text grows ("7h" → "7h 30m").
                            Text("\(formatEffort(Double(draft), dayLength: dayLength)) left").monospacedDigit()
                                .frame(width: 130, alignment: .leading)
                        }
                        HStack {
                            Button("Cancel") { editing = false }
                            Spacer()
                            Button("Set") {
                                editing = false
                                let day = LocalDay(date: Date()).description
                                Task { await app.send(.setRemaining(id: task.id, minutes: draft, effortMinutes: effortMinutes, day: day)) }
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding().frame(width: 240)
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

/// The parts of a task: tick off, rename, estimate, reorder, delete, add (specs/tasks "Parts of a task", subtasks S5).
struct TaskPartsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    let task: TaskItem
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Parts").foregroundStyle(.secondary)
                if !task.parts.isEmpty {
                    Text("\(task.parts.filter(\.done).count)/\(task.parts.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    let unestimated = task.hasEstimatedParts ? task.parts.filter { !$0.done && $0.effort == nil }.count : 0
                    if unestimated > 0 { Text("\(unestimated) without estimate").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if allDone {
                HStack {
                    Label("All parts done", systemImage: "checkmark.seal").foregroundStyle(.green)
                    Button("Complete task") { send(.setStatus(id: task.id, .done)) }.disabled(!app.canWrite)
                }
                .font(.callout)
            }
            if !task.parts.isEmpty {
                List {
                    ForEach(task.parts) { part in PartRow(part: part, count: task.parts.count, index: index(of: part)) }
                        .onMove { from, to in
                            guard let source = from.first else { return }
                            // `to` counts the moved row itself; the command wants the index among the others.
                            send(.movePart(id: task.parts[source].id, toIndex: to > source ? to - 1 : to))
                        }
                }
                .listStyle(.plain).scrollDisabled(true)
                .frame(height: CGFloat(task.parts.count) * 28)
            }
            TextField("Add part", text: $newTitle)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                .onSubmit {
                    let title = newTitle.trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { return }
                    send(.addPart(taskID: task.id, title: title, effort: nil))
                    newTitle = ""
                }
                .disabled(!app.canWrite)
        }
    }

    private var allDone: Bool { !task.parts.isEmpty && task.parts.allSatisfy(\.done) && task.status == .open }
    private func index(of part: TaskPart) -> Int { task.parts.firstIndex(of: part) ?? 0 }
    private func send(_ c: Command) { Task { await app.send(c) } }
}

private struct PartRow: View {
    @Environment(AppModel.self) private var app
    let part: TaskPart
    let count: Int
    let index: Int
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { send(.updatePart(id: part.id, PartPatch(done: !part.done))) } label: {
                Image(systemName: part.done ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain).disabled(!app.canWrite).help(part.done ? "Reopen" : "Tick off")
            TextField("Part", text: $title).textFieldStyle(.plain)
                .strikethrough(part.done).foregroundStyle(part.done ? .secondary : .primary)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { _, f in if !f { save() } }
            Menu {
                ForEach(Effort.allCases, id: \.self) { e in Button(e.label) { send(.updatePart(id: part.id, PartPatch(effort: .some(e)))) } }
                Divider()
                Button("None") { send(.updatePart(id: part.id, PartPatch(effort: .some(nil)))) }
            } label: { Text(part.effort?.label ?? "–").font(.caption) }
            .menuStyle(.borderlessButton).fixedSize().help("Effort of this part")
        }
        .contextMenu {
            Button("Move Up") { send(.movePart(id: part.id, toIndex: index - 1)) }.disabled(index == 0)
            Button("Move Down") { send(.movePart(id: part.id, toIndex: index + 1)) }.disabled(index >= count - 1)
            Divider()
            Button("Delete Part", role: .destructive) { send(.deletePart(id: part.id)) }
        }
        .onAppear { title = part.title }
        .onChange(of: part.title) { _, t in if !focused { title = t } }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { title = part.title; return }
        guard trimmed != part.title else { return }
        send(.updatePart(id: part.id, PartPatch(title: trimmed)))
    }
    private func send(_ c: Command) { Task { await app.send(c) } }
}
