import SwiftUI
import WorkDashCore

enum TaskEditorTarget: Identifiable {
    case new(due: Due?)
    case edit(String)
    var id: String {
        switch self {
        case .new(let due): return "new-\(due?.day ?? "")"
        case .edit(let id): return id
        }
    }
}

extension Priority {
    var label: String { rawValue.capitalized }
    var symbol: String? {
        switch self {
        case .urgent: return "exclamationmark.2"
        case .high: return "exclamationmark"
        case .low: return "arrow.down"
        case .normal, .none: return nil
        }
    }
    var tint: Color {
        switch self {
        case .urgent: return .red
        case .high: return .orange
        case .normal: return .primary
        case .low, .none: return .secondary
        }
    }
}

/// One task line, used in the day view and the task list. Completion and priority are inline edits.
struct TaskRow: View {
    @Environment(AppModel.self) private var app
    let task: TaskItem
    var overdue = false
    var backFromSnooze = false
    var onEdit: () -> Void
    /// Completion shown immediately, committed after a short delay so the tick is visible (and can be undone by clicking again).
    @State private var pendingCompletion: Task<Void, Never>?

    private var showsDone: Bool { task.status == .done || pendingCompletion != nil }

    private func toggleDone() {
        if let pending = pendingCompletion {
            pending.cancel()                 // second click within the delay: keep the task open
            pendingCompletion = nil
            return
        }
        if task.status == .done {
            Task { await app.send(.setStatus(id: task.id, .open)) }
            return
        }
        pendingCompletion = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await app.send(.setStatus(id: task.id, .done))
            pendingCompletion = nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleDone) {
                Image(systemName: showsDone ? "checkmark.circle.fill" : "circle").imageScale(.large)
                    .foregroundStyle(pendingCompletion != nil ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)
            .disabled(!app.canWrite)
            .help(task.status == .done ? "Reopen" : (pendingCompletion != nil ? "Click again to keep it open" : "Complete"))

            if let symbol = task.priority.symbol {
                Image(systemName: symbol).foregroundStyle(task.priority.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).strikethrough(showsDone || task.status == .dropped)
                    .foregroundStyle(pendingCompletion != nil ? .secondary : .primary)
                HStack(spacing: 6) {
                    if overdue { Text("overdue").font(.caption.bold()).foregroundStyle(.red) }
                    if backFromSnooze { Text("back from snooze").font(.caption.bold()).foregroundStyle(.blue) }
                    if let due = task.due { Text(Self.dueText(due)).font(.caption).foregroundStyle(.secondary) }
                    if task.status == .snoozed, let until = task.snoozedUntil { Text("snoozed until \(until)").font(.caption).foregroundStyle(.secondary) }
                    ForEach(task.tags, id: \.self) { TagChip(name: $0) }
                }
            }
            Spacer()
            Menu {
                ForEach(Priority.allCases.reversed(), id: \.self) { p in
                    Button(p.label) { Task { await app.send(.updateTask(id: task.id, TaskPatch(priority: p))) } }
                }
            } label: { Text(task.priority.label).font(.caption) }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(!app.canWrite)
            .help("Priority")
        }
        .animation(.easeOut(duration: 0.2), value: pendingCompletion != nil)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu { TaskActions(task: task, onEdit: onEdit) }
        .padding(.vertical, 2)
    }

    static func dueText(_ due: Due) -> String {
        guard let date = due.date() else { return due.day }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = due.time == nil ? .none : .short
        return f.string(from: date)
    }
}

struct TaskActions: View {
    @Environment(AppModel.self) private var app
    let task: TaskItem
    var onEdit: () -> Void

    var body: some View {
        Button("Edit…", action: onEdit)
        Divider()
        // Count from the later of today and the current snooze date, so an already snoozed task can be pushed further.
        let base = Self.snoozeBase(for: task)
        Button(task.status == .snoozed ? "Snooze 1 More Day" : "Snooze until Tomorrow") { snooze(base.adding(days: 1)) }
        Button("Snooze until Next Monday") { snooze(Self.nextMonday(after: base)) }
        Button("Snooze until…", action: onEdit)
        Divider()
        if task.status != .open { Button("Reopen") { send(.setStatus(id: task.id, .open)) } }
        if task.status != .dropped { Button("Drop") { send(.setStatus(id: task.id, .dropped)) } }
        Button("Delete", role: .destructive) { send(.deleteTask(id: task.id)) }
    }

    private func snooze(_ day: LocalDay) { send(.setStatus(id: task.id, .snoozed, snoozedUntil: day.description)) }
    private func send(_ c: Command) { Task { await app.send(c) } }

    static func snoozeBase(for task: TaskItem, today: LocalDay = LocalDay(date: Date())) -> LocalDay {
        guard let s = task.snoozedUntil, let until = LocalDay(s), until > today else { return today }
        return until
    }

    static func nextMonday(after day: LocalDay) -> LocalDay {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: day.interval().start)   // 1 = Sunday, 2 = Monday
        let delta = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7   // days until the next Monday, never 0
        return day.adding(days: delta)
    }
}

struct TagChip: View {
    let name: String
    var body: some View {
        Text(name).font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
            .background(.secondary.opacity(0.15)).clipShape(Capsule())
    }
}

/// Task list (specs/tasks "Task list"): Open / Done / Dropped, filtered by the selected tag.
struct TaskListView: View {
    @Environment(AppModel.self) private var app
    @Environment(TasksModel.self) private var tasks
    @State private var editing: TaskEditorTarget?

    var body: some View {
        @Bindable var tasks = tasks
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("", selection: $tasks.mode) {
                    Text("Open").tag(TaskListMode.open)
                    Text("Done").tag(TaskListMode.done)
                    Text("Dropped").tag(TaskListMode.dropped)
                }
                .pickerStyle(.segmented).fixedSize()
                if let tag = tasks.tagFilter {
                    HStack(spacing: 4) {
                        TagChip(name: tag.display)
                        Button { tasks.tagFilter = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Button { editing = .new(due: nil) } label: { Label("New Task", systemImage: "plus") }
                    .disabled(!app.canWrite)
            }
            .padding()
            Divider()
            if tasks.list.isEmpty {
                Text(tasks.mode == .open ? "No open tasks" : "Nothing here").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(tasks.list) { task in
                    TaskRow(task: task, onEdit: { editing = .edit(task.id) })
                }
            }
        }
        .sheet(item: $editing) { TaskEditor(target: $0) }
    }
}

/// Edit form with explicit confirm (specs/tasks "Create a task", "Edit a task", "Task fields").
struct TaskEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(TasksModel.self) private var tasks
    @Environment(\.dismiss) private var dismiss
    let target: TaskEditorTarget

    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Priority = .none
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var dueHasTime = false
    @State private var tagNames: [String] = []
    @State private var pendingTag = ""
    @State private var status: TaskStatus = .open
    @State private var snoozeDate = Date().addingTimeInterval(86_400)
    @State private var original: TaskItem?
    @State private var titleMissing = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original == nil ? "New Task" : "Edit Task").font(.title3.bold())
            Form {
                TextField("Title", text: $title, prompt: Text("Required"))
                    .overlay(alignment: .trailing) {
                        if titleMissing { Text("Title is required").font(.caption).foregroundStyle(.red).padding(.trailing, 4) }
                    }
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases.reversed(), id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Due date", isOn: $hasDue)
                if hasDue {
                    Toggle("With time", isOn: $dueHasTime)
                    DatePicker("Due", selection: $dueDate, displayedComponents: dueHasTime ? [.date, .hourAndMinute] : [.date])
                }
                if original != nil {
                    Picker("Status", selection: $status) {
                        Text("Open").tag(TaskStatus.open)
                        Text("Snoozed").tag(TaskStatus.snoozed)
                        Text("Done").tag(TaskStatus.done)
                        Text("Dropped").tag(TaskStatus.dropped)
                    }
                    if status == .snoozed {
                        DatePicker("Snooze until", selection: $snoozeDate, displayedComponents: [.date])
                    }
                }
                TagField(tags: $tagNames, input: $pendingTag)
                LabeledContent("Notes") {
                    TextEditor(text: $notes).font(.body).frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? "Create" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !app.canWrite)
            }
        }
        .padding()
        .frame(width: 600)
        .onAppear(perform: load)
    }

    private func load() {
        switch target {
        case .new(let due):
            if let due, let date = due.date() { hasDue = true; dueDate = date; dueHasTime = due.time != nil }
        case .edit(let id):
            guard let t = tasks.task(id: id) else { error = "This task no longer exists."; return }
            original = t
            title = t.title; notes = t.body; priority = t.priority; tagNames = t.tags; status = t.status
            if let due = t.due, let date = due.date() { hasDue = true; dueDate = date; dueHasTime = due.time != nil }
            if let s = t.snoozedUntil, let d = LocalDay(s) { snoozeDate = d.interval().start }
        }
    }

    private func save() async {
        titleMissing = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !titleMissing else { return }
        // A tag typed but not confirmed with Enter is still meant to be added.
        if !pendingTag.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                let name = try TagName(pendingTag)
                if !tagNames.contains(where: { TagName.key(for: $0) == name.key }) { tagNames.append(name.display) }
                pendingTag = ""
            } catch {
                self.error = (error as? TagName.Invalid)?.description ?? "\(error)"
                return
            }
        }
        saving = true; defer { saving = false }
        let due: Due? = hasDue ? Due(date: dueDate, includeTime: dueHasTime) : nil
        // Validate tags locally for a direct message; the agent validates again.
        for t in tagNames {
            do { _ = try TagName(t) } catch { self.error = (error as? TagName.Invalid)?.description ?? "\(error)"; return }
        }

        if let original {
            // One command, so one save is one undo step.
            var patch = TaskPatch()
            if title != original.title { patch.title = title }
            if notes != original.body { patch.body = notes }
            if priority != original.priority { patch.priority = priority }
            if due != original.due { patch.due = .some(due) }
            if Set(tagNames.map(TagName.key)) != Set(original.tags.map(TagName.key)) { patch.tags = tagNames }
            let snoozeDay = LocalDay(date: snoozeDate).description
            if status != original.status || (status == .snoozed && snoozeDay != original.snoozedUntil) {
                patch.status = status
                patch.snoozedUntil = status == .snoozed ? snoozeDay : nil
            }
            if patch != TaskPatch(), case .failure(let f) = await app.send(.updateTask(id: original.id, patch)) { error = f.message; return }
        } else {
            let r = await app.send(.createTask(TaskDraft(title: title, body: notes, priority: priority, due: due, tags: tagNames)))
            if case .failure(let f) = r { error = f.message; return }
        }
        dismiss()
    }
}

/// Tag entry with chips and autocomplete (specs/tags "Assign and remove tags", "Tag autocomplete").
/// One form row: label "Tags"; chips wrap, the input field sits below them at full width.
struct TagField: View {
    @Environment(TasksModel.self) private var tasks
    @Binding var tags: [String]
    @Binding var input: String
    @State private var problem: String?

    var body: some View {
        LabeledContent("Tags") {
            VStack(alignment: .leading, spacing: 6) {
                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 2) {
                                TagChip(name: tag)
                                Button { tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark").font(.caption2) }
                                    .buttonStyle(.plain).help("Remove tag")
                            }
                        }
                    }
                }
                TextField("Add tag", text: $input, prompt: Text("Add tag, e.g. person/alex"))
                    .labelsHidden()
                    .onSubmit(add)
                    .onChange(of: input) { problem = nil }
                if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                let suggestions = input.isEmpty ? [] : tasks.autocomplete(input).filter { s in !tags.contains { TagName.key(for: $0) == TagName.key(for: s) } }
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions.prefix(6), id: \.self) { s in
                            Button(s) {
                                // A segment completion (e.g. "project" while "project/atlas" exists) continues typing;
                                // a full tag is added directly.
                                if suggestions.contains(where: { $0.hasPrefix(s + "/") }) {
                                    input = s + "/"
                                } else {
                                    input = s
                                    add()
                                }
                            }
                            .buttonStyle(.link).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func add() {
        do {
            let name = try TagName(input)
            if !tags.contains(where: { TagName.key(for: $0) == name.key }) { tags.append(name.display) }
            input = ""
        } catch {
            problem = (error as? TagName.Invalid)?.description ?? "\(error)"
        }
    }
}

/// Minimal wrapping layout for chips: places subviews left to right and wraps to new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
