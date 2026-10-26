import SwiftUI
import WorkDashCore

/// The new-task form's preset (tasks are edited on their task page, specs/tasks "Task page").
enum TaskEditorTarget: Identifiable {
    case new(due: Due?)
    var id: String {
        switch self {
        case .new(let due): return "new-\(due?.day ?? "")"
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
    var onEdit: () -> Void
    /// Planning note (day view).
    var note: PlanNote? = nil
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
                    if let due = task.due { Text(Self.dueText(due)).font(.caption).foregroundStyle(.secondary) }
                    if let effort = task.effort { EffortChip(effort: effort) }
                    if let note, !note.text.isEmpty { Text(note.text).font(.caption.bold()).foregroundStyle(note.color).help(note.help) }
                    if task.isSnoozed(today: LocalDay(date: Date())), let until = task.snoozedUntil.flatMap(LocalDay.init) {
                        Label("until \(DayView.title(for: until))", systemImage: "moon.zzz").font(.caption).foregroundStyle(.blue)
                    }
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
        .onTapGesture(perform: onEdit)          // single click opens, like page rows; the circle, priority and tags keep their own clicks
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
    /// Opens the task page; nil on the task page itself.
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit { Button("Open", action: onEdit) }
        Divider()
        // Count from the later of today and the current snooze date, so an already snoozed task can be pushed further.
        let base = Self.snoozeBase(for: task)
        Button(task.status == .snoozed ? "Snooze 1 More Day" : "Snooze until Tomorrow") { snooze(base.adding(days: 1)) }
        Button("Snooze until Next Monday") { snooze(Self.nextMonday(after: base)) }
        if let onEdit { Button("Snooze until…", action: onEdit) }
        Divider()
        Menu("Effort") {
            ForEach(Effort.allCases, id: \.self) { e in
                Button(e.label) { send(.updateTask(id: task.id, TaskPatch(effort: .some(e)))) }
            }
            Divider()
            Button("None") { send(.updateTask(id: task.id, TaskPatch(effort: .some(nil)))) }
        }
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

/// Effort size chip (specs/tasks "Task fields").
struct EffortChip: View {
    let effort: Effort
    var body: some View {
        Text(effort.label).font(.caption2.bold()).monospaced().padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.5)))
            .foregroundStyle(.secondary).help("Effort")
    }
}

struct TagChip: View {
    @Environment(Navigation.self) private var nav
    let name: String
    /// Clicking opens the tag page (specs/tag-pages "From a chip"); off in editors.
    var opensTagPage = true
    var body: some View {
        Text(name).font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
            .background(.secondary.opacity(0.15)).clipShape(Capsule())
            .onTapGesture { if opensTagPage { nav.go(.tag(name)) } }
            .help(opensTagPage ? "Open tag page" : "")
    }
}

/// Task list (specs/tasks "Task list"): Open / Done / Dropped, filtered by the selected tag.
struct TaskListView: View {
    @Environment(Navigation.self) private var nav
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
                    TaskRow(task: task, onEdit: { nav.go(.task(task.id)) })
                        .draggableItem(.task, id: task.id, title: task.title)
                }
            }
        }
        .sheet(item: $editing) { TaskEditor(target: $0) }
    }
}

/// New-task form with explicit confirm (specs/tasks "Create a task", "Edit a task").
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
    @State private var titleMissing = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Task").font(.title3.bold())
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
                TagField(tags: $tagNames, input: $pendingTag)
                LabeledContent("Notes") {
                    // Markdown with links; saved with the form (explicit confirm, specs/tasks "Edit a task").
                    WDMarkdownEditor(text: notes, onChange: { notes = $0 }).frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { Task { await save() } }
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

        let r = await app.send(.createTask(TaskDraft(title: title, body: notes, priority: priority, due: due, tags: tagNames)))
        if case .failure(let f) = r { error = f.message; return }
        dismiss()
    }
}

/// Tag entry: chips plus an "Add tag" menu that mirrors the tag hierarchy (specs/tags "Tag picker").
/// `input` holds a typed-but-unconfirmed new tag name (committed on save by the editors).
struct TagField: View {
    @Environment(TasksModel.self) private var tasks
    @Binding var tags: [String]
    @Binding var input: String
    @State private var newTagPrefix: String?
    @State private var problem: String?
    @FocusState private var newTagFocused: Bool

    /// A node of the picker tree built from all existing tag names.
    struct Node: Identifiable {
        var id: String { path }
        let segment: String
        let path: String
        var isTag: Bool
        var children: [Node]
    }

    static func tree(_ names: [String]) -> [Node] {
        func build(_ prefix: String, _ paths: [[String]]) -> [Node] {
            let groups = Dictionary(grouping: paths.filter { !$0.isEmpty }, by: { $0[0] })
            return groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { segment in
                let path = prefix.isEmpty ? segment : prefix + "/" + segment
                let rest = groups[segment]!.map { Array($0.dropFirst()) }
                return Node(segment: segment, path: path, isTag: rest.contains { $0.isEmpty }, children: build(path, rest))
            }
        }
        return build("", names.map { $0.split(separator: "/").map(String.init) })
    }

    var body: some View {
        LabeledContent("Tags") {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 2) {
                            TagChip(name: tag, opensTagPage: false)
                            Button { tags.removeAll { $0 == tag } } label: { Image(systemName: "xmark").font(.caption2) }
                                .buttonStyle(.plain).help("Remove tag")
                        }
                    }
                    Menu {
                        ForEach(Self.tree(tasks.allTagNames())) { node in nodeMenu(node) }
                        Divider()
                        Button("New tag…") { newTagPrefix = "" }
                    } label: { Label("Add tag", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                if let prefix = newTagPrefix {
                    HStack {
                        Text(prefix.isEmpty ? "New tag" : "New tag in \(prefix)/").foregroundStyle(.secondary)
                        TextField("name", text: $input).frame(minWidth: 160).onSubmit { commit(prefix) }
                            .focused($newTagFocused)
                            .onExitCommand { newTagPrefix = nil; input = ""; problem = nil }
                        Button("Add") { commit(prefix) }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { newTagPrefix = nil; input = ""; problem = nil }
                    }
                    .onChange(of: input) { problem = nil }
                }
                if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
            }
        }
        // Focus the name field as soon as "New tag…" is chosen (after the menu has closed).
        .onChange(of: newTagPrefix) { _, prefix in
            guard prefix != nil else { return }
            DispatchQueue.main.async { newTagFocused = true }
        }
    }

    /// A submenu for a group (with "use this tag" if it is one, its children and "New tag in …"), a button for a leaf.
    private func nodeMenu(_ node: Node) -> AnyView {
        let taken = tags.contains { TagName.key(for: $0) == TagName.key(for: node.path) }
        if node.children.isEmpty {
            return AnyView(Button(node.segment) { add(node.path) }.disabled(taken))
        }
        return AnyView(Menu(node.segment) {
            if node.isTag { Button("\(node.path)") { add(node.path) }.disabled(taken); Divider() }
            ForEach(node.children) { child in nodeMenu(child) }
            Divider()
            Button("New tag in \(node.path)/…") { newTagPrefix = node.path }
        })
    }

    private func add(_ name: String) {
        guard !tags.contains(where: { TagName.key(for: $0) == TagName.key(for: name) }) else { return }
        tags.append(name)
    }

    private func commit(_ prefix: String) {
        let raw = prefix.isEmpty ? input : prefix + "/" + input
        do {
            let name = try TagName(raw)
            add(name.display)
            input = ""; newTagPrefix = nil
        } catch {
            problem = (error as? TagName.Invalid)?.description ?? "\(error)"
        }
    }
}

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
