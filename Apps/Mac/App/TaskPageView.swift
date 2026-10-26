import SwiftUI
import WorkDashCore

struct TaskDetail: Equatable {
    var task: TaskItem?
    var backlinks: [Backlink]
}

/// A task in the main area, laid out like a page (specs/tasks "Task page"): title, field row, notes, backlinks.
/// Every change is saved at once; each field change and each notes edit session is one undo step.
struct TaskPageView: View {
    @Environment(AppModel.self) private var app
    @Environment(WikiModel.self) private var wiki
    @Environment(Navigation.self) private var nav
    @Environment(Clock.self) private var clock
    let id: String

    @State private var live = Live<TaskDetail>()
    @State private var title = ""
    @State private var tags: [String] = []
    @State private var pendingTag = ""
    @State private var editing: Bool?
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if let detail = live.value, let task = detail.task {
                content(task, backlinks: detail.backlinks)
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
                TaskDetail(task: try TaskQueries.task(db, id: id), backlinks: try LinkQueries.backlinks(db, to: id))
            }
        }
        .onChange(of: live.value?.task) { _, task in
            guard let task else { return }
            if !titleFocused { title = task.title }
            tags = task.tags
            if editing == nil { editing = task.body.isEmpty }
        }
    }

    private func content(_ task: TaskItem, backlinks: [Backlink]) -> some View {
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
            Form { TagField(tags: $tags, input: $pendingTag) }
                .formStyle(.columns).padding(.horizontal)
                .onChange(of: tags) { _, new in
                    guard new != task.tags else { return }
                    send(.updateTask(id: task.id, TaskPatch(tags: new)))
                }
            Divider().padding(.top, 8)

            if editing == true {
                WDMarkdownEditor(text: task.body, onCommit: { text, session in
                    send(.updateTask(id: task.id, TaskPatch(body: text, session: session)))
                })
                .frame(maxHeight: .infinity)
                Divider()
                BacklinksView(backlinks: backlinks).padding().frame(maxHeight: 180, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if task.body.isEmpty {
                            Text("No notes – switch to Edit (⌘E) to write.").foregroundStyle(.secondary)
                        } else {
                            WDMarkdownReadView(text: task.body) { new in
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
        HStack(spacing: 16) {
            Picker("Priority", selection: Binding(get: { task.priority }, set: { p in
                send(.updateTask(id: task.id, TaskPatch(priority: p)))
            })) {
                ForEach(Priority.allCases.reversed(), id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()

            Toggle("Due", isOn: Binding(get: { task.due != nil }, set: { on in
                let due: Due? = on ? Due(day: clock.today.description) : nil
                send(.updateTask(id: task.id, TaskPatch(due: .some(due))))
            }))
            if let due = task.due {
                DatePicker("", selection: Binding(get: { due.date() ?? Date() }, set: { date in
                    send(.updateTask(id: task.id, TaskPatch(due: .some(Due(date: date, includeTime: due.time != nil)))))
                }), displayedComponents: due.time == nil ? [.date] : [.date, .hourAndMinute])
                .labelsHidden().fixedSize()
                Toggle("Time", isOn: Binding(get: { due.time != nil }, set: { on in
                    let date = due.date() ?? Date()
                    send(.updateTask(id: task.id, TaskPatch(due: .some(Due(date: on ? date.addingTimeInterval(9 * 3600) : date, includeTime: on)))))
                }))
            }

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
            Spacer()
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
