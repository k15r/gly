import SwiftUI
import GlyCore

/// The new-task form's preset (tasks are edited on their task page, specs/tasks "Task page").
enum TaskEditorTarget: Identifiable {
    /// `tags`: the browser view's tag filters (specs/item-browser "Create from a view").
    case new(due: Due?, tags: [String] = [])
    var id: String {
        switch self {
        case .new(let due, let tags): return "new-\(due?.day ?? "")-\(tags.joined(separator: ","))"
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
/// "Done for today" on a planning row of today's view (task-progress P4): what today asks for and what's ticked off.
struct TodaysPart: Equatable {
    let neededMinutes: Int
    let recordedMinutes: Int?
}

struct TaskRow: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    @Environment(Clock.self) private var clock
    let task: TaskItem
    /// The day the row is shown for (the day view's day); nil = today.
    var day: LocalDay?
    /// The task's Today-list entry for that day, if any (for can't fit / needs work).
    var plan: TodayItem?
    var onEdit: () -> Void
    /// Planning note (day view).
    var note: PlanNote? = nil
    /// Offers "done for today" (today's planning rows only).
    var todaysPart: TodaysPart?
    /// Completion shown immediately, committed after a short delay so the tick is visible (and can be undone by clicking again).
    @State private var pendingCompletion: Task<Void, Never>?
    @State private var hovering = false
    @State private var snoozing = false
    @State private var estimating = false

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

    /// Status bar, title line with the plan note, compact chips, hover quick actions (specs/appearance "Task rows", status-colors C3).
    var body: some View {
        let shownDay = day ?? clock.today
        let status = RowStatus.of(task, day: shownDay, today: clock.today, plan: plan, dayLength: planning.hours.minutesPerDay)
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(status?.kind.color ?? .clear).frame(width: 3)
                .help(status?.tooltip ?? "")
            Button(action: toggleDone) {
                Image(systemName: showsDone ? "checkmark.circle.fill" : "circle").imageScale(.large)
                    .foregroundStyle(showsDone ? StatusKind.done.color : (pendingCompletion != nil ? Color.accentColor : .primary))
            }
            .buttonStyle(.plain)
            .disabled(!app.canWrite)
            .help(task.status == .done ? "Reopen" : (pendingCompletion != nil ? "Click again to keep it open" : "Complete"))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let symbol = task.priority.symbol {
                        Image(systemName: symbol).foregroundStyle(task.priority.tint).help("Priority \(task.priority.label)")
                    }
                    Text(task.title).strikethrough(showsDone || task.status == .dropped)
                        .foregroundStyle(pendingCompletion != nil ? .secondary : .primary)
                    if let note, !note.text.isEmpty {
                        Label(note.text, systemImage: note.status?.symbol ?? "clock")
                            .labelStyle(.titleAndIcon).font(.caption.bold()).foregroundStyle(note.color).help(note.help)
                    } else if let status, status.kind != .done {
                        Label(Self.shortReason(status.kind), systemImage: status.kind.symbol)
                            .font(.caption.bold()).foregroundStyle(status.kind.color).help(status.tooltip)
                    }
                }
                chips(status: status, shownDay: shownDay)
            }
            Spacer(minLength: 4)
            if let todaysPart { todaysPartButton(todaysPart) }
            if hovering && task.status != .done { quickActions }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.2), value: pendingCompletion != nil)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onEdit)          // single click opens, like page rows; the circle, chips and actions keep their own clicks
        .contextMenu { TaskActions(task: task, onEdit: onEdit) }
        .padding(.vertical, 2)
    }

    static func shortReason(_ kind: StatusKind) -> String {
        switch kind {
        case .cantFit: "can't fit"
        case .overdue: "overdue"
        case .dueToday: "due"
        case .needsWork: "needs work"
        case .backFromSnooze: "back from snooze"
        case .done: "done"
        }
    }

    /// Effort (with what's left), due date, parts, snooze date and tags in the small chip style.
    @ViewBuilder
    private func chips(status: RowStatus?, shownDay: LocalDay) -> some View {
        let dayLength = planning.hours.minutesPerDay
        let parts = task.parts
        let left = task.remaining(sizes: planning.sizes, dayMinutes: dayLength)
        let progressed = task.workedMinutes != 0 || parts.contains { $0.estimate != nil }
        let snoozedUntil = task.isSnoozed(today: clock.today) ? task.snoozedUntil.flatMap(LocalDay.init) : nil
        if task.effort != nil || progressed || task.due != nil || !parts.isEmpty || snoozedUntil != nil || !task.tags.isEmpty {
            FlowLayout(spacing: 4) {
                if let effort = task.effort {
                    let text = progressed && left != nil ? "\(effort.label) · \(left == 0 ? "nothing" : formatEffort(Double(left!), dayLength: dayLength)) left" : effort.label
                    Label(text, systemImage: "gauge.with.dots.needle.33percent").modifier(ChipStyle(compact: true)).help("Effort")
                } else if progressed, let left {
                    Label("\(formatEffort(Double(left), dayLength: dayLength)) left", systemImage: "gauge.with.dots.needle.33percent")
                        .modifier(ChipStyle(compact: true)).help("Left from the estimated checklist items")
                }
                if let due = task.due {
                    let overdue = status?.kind == .overdue || status?.kind == .cantFit
                    Label(TaskPropertyRow.shortDue(due), systemImage: "calendar")
                        .modifier(ChipStyle(tint: overdue ? StatusKind.overdue.color : .primary, compact: true)).help("Due date")
                }
                if !parts.isEmpty {
                    Label("\(parts.filter(\.done).count)/\(parts.count)", systemImage: "checklist")
                        .modifier(ChipStyle(compact: true)).help("Checklist items done")
                }
                if let snoozedUntil {
                    Label("until \(DayView.weekday(snoozedUntil))", systemImage: "moon.zzz")
                        .modifier(ChipStyle(tint: StatusKind.backFromSnooze.color, compact: true)).help("Snoozed until \(DayView.title(for: snoozedUntil))")
                }
                ForEach(task.tags, id: \.self) { tag in
                    TagChip(name: tag)
                }
            }
        }
    }

    /// Snooze, effort, open (on hover); the same actions stay in the context menu.
    private var quickActions: some View {
        HStack(spacing: 2) {
            Button { snoozing = true } label: { Image(systemName: "moon.zzz") }
                .help("Snooze")
                .popover(isPresented: $snoozing, arrowEdge: .bottom) {
                    SnoozePicker(task: task, until: task.isSnoozed(today: clock.today) ? task.snoozedUntil.flatMap(LocalDay.init) : nil,
                                 today: clock.today) { snoozing = false }.padding(12)
                }
            Button { estimating = true } label: { Image(systemName: "gauge.with.dots.needle.33percent") }
                .help("Effort")
                .popover(isPresented: $estimating, arrowEdge: .bottom) { EffortPicker(task: task) { estimating = false }.padding(12) }
            Button(action: onEdit) { Image(systemName: "arrow.up.forward.square") }.help("Open")
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
        .disabled(!app.canWrite)
    }

    /// Records what today asks for as worked today, or takes it back (specs/daily-planning "Record today's part").
    private func todaysPartButton(_ part: TodaysPart) -> some View {
        let today = LocalDay(date: Date()).description
        let dayLength = planning.hours.minutesPerDay
        return Button {
            if part.recordedMinutes != nil {
                Task { await app.send(.undoTodaysPart(id: task.id, day: today)) }
            } else {
                Task { await app.send(.recordWork(id: task.id, day: today, minutes: part.neededMinutes, kind: .part)) }
            }
        } label: {
            if let recorded = part.recordedMinutes {
                Label("today's part done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    .help("\(formatEffort(Double(recorded), dayLength: dayLength)) recorded for today – click to take it back")
            } else {
                Label("done for today", systemImage: "checkmark.circle")
                    .help("Record today's \(formatEffort(Double(part.neededMinutes), dayLength: dayLength)) as done; the plan continues with what's left")
            }
        }
        .buttonStyle(.borderless).font(.caption)
        .disabled(!app.canWrite)
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
    @Environment(PlanningModel.self) private var planning
    @Environment(CalendarModel.self) private var calendars
    let task: TaskItem
    /// Opens the task page; nil on the task page itself.
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit { Button("Open", action: onEdit) }
        Divider()
        // Count from the later of today and the current snooze date, so an already snoozed task can be pushed further.
        let base = Self.snoozeBase(for: task)
        // What a snooze costs (specs/tasks "Snooze shows its cost"): the due date stays; warn when the task won't fit anymore.
        if let due = task.due, let dueDay = LocalDay(due.day) {
            Section("Due \(DayView.shortTitle(for: dueDay)) stays") { snoozeOptions(base) }
        } else {
            snoozeOptions(base)
        }
        Divider()
        Menu("Priority") {
            ForEach(Priority.allCases.reversed(), id: \.self) { p in
                Button(p.label) { send(.updateTask(id: task.id, TaskPatch(priority: p))) }
            }
        }
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

    @ViewBuilder private func snoozeOptions(_ base: LocalDay) -> some View {
        snoozeButton(task.status == .snoozed ? "Snooze 1 More Day" : "Snooze until Tomorrow", until: base.adding(days: 1))
        snoozeButton("Snooze until Next Monday", until: Self.nextMonday(after: base))
        if let onEdit { Button("Snooze until…", action: onEdit) }
    }

    private func snoozeButton(_ title: String, until day: LocalDay) -> some View {
        Button { snooze(day) } label: {
            if planning.fits(task, returningOn: day, calendars: calendars) == false {
                Label("\(title) – won't fit anymore", systemImage: "exclamationmark.triangle")
            } else {
                Text(title)
            }
        }
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
    @Environment(TagColorModel.self) private var tagColors
    let name: String
    /// Clicking opens the tag page (specs/tag-pages "From a chip"); off in editors.
    var opensTagPage = true
    /// The tag that tells same-titled items apart (shown semibold instead of repeating it after the title).
    var emphasized = false
    var body: some View {
        let tint = tagColors.color(name)
        Text(name).font(.caption).fontWeight(emphasized ? .semibold : .regular).padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15)).clipShape(Capsule())
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
                    GlyMarkdownEditor(text: notes, onChange: { notes = $0 }).frame(minHeight: 140)
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
        case .new(let due, let tags):
            if let due, let date = due.date() { hasDue = true; dueDate = date; dueHasTime = due.time != nil }
            if tagNames.isEmpty { tagNames = tags }
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
/// A tag as a property chip in its color; a click opens the tag page, ✕ (on hover) removes it (task-properties T5).
struct RemovableTagChip: View {
    @Environment(Navigation.self) private var nav
    @Environment(TagColorModel.self) private var tagColors
    let name: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "tag")
            Text(name)
            Button(action: remove) { Image(systemName: "xmark").font(.caption2.bold()) }
                .buttonStyle(.plain).help("Remove tag")
                .opacity(hovering ? 0.8 : 0).frame(width: hovering ? nil : 0)
        }
        .modifier(ChipStyle(hovering: hovering, tint: tagColors.color(name), tinted: true))
        .onHover { hovering = $0 }
        .onTapGesture { nav.go(.tag(name)) }
        .help("Open tag page")
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// "+ Tag" with the dashed look of an empty property chip.
private struct AddTagLabel: View {
    @State private var hovering = false
    var body: some View {
        Label("+ Tag", systemImage: "tag").modifier(ChipStyle(isEmpty: true, hovering: hovering)).onHover { hovering = $0 }
    }
}

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
        // Tags as chips with ✕ on hover and a faded "+ Tag" (task-properties T4, T5); same on tasks, pages and meetings.
        VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        RemovableTagChip(name: tag) { tags.removeAll { $0 == tag } }
                    }
                    Menu {
                        ForEach(Self.tree(tasks.allTagNames())) { node in nodeMenu(node) }
                        Divider()
                        Button("New tag…") { newTagPrefix = "" }
                    } label: {
                        AddTagLabel()
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("Add a tag")
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
        // Focus the name field as soon as "New tag…" is chosen (after the menu has closed).
        .onChange(of: newTagPrefix) { _, prefix in
            guard prefix != nil else { return }
            DispatchQueue.main.async { newTagFocused = true }
        }
    }

    /// A submenu for a group (the group itself first, its children and "New tag in …"), a button for a leaf.
    /// A group is a usable tag even when only tags below it exist (as in the sidebar): choosing it creates it.
    private func nodeMenu(_ node: Node) -> AnyView {
        let taken = tags.contains { TagName.key(for: $0) == TagName.key(for: node.path) }
        if node.children.isEmpty {
            return AnyView(Button(node.segment) { add(node.path) }.disabled(taken))
        }
        return AnyView(Menu(node.segment) {
            Button("Tag with “\(node.path)”") { add(node.path) }.disabled(taken)
            Divider()
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
