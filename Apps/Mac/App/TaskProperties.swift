import SwiftUI
import GlyCore

/// A compact property: icon and value in a capsule, faded "+ Name" when empty; a click opens its popover
/// (specs/tasks "Task page", task-properties T1).
struct PropertyChip<Popup: View>: View {
    let symbol: String
    let text: String
    var tint: Color = .primary
    var isEmpty = false
    let help: String
    @ViewBuilder let popup: (_ close: @escaping () -> Void) -> Popup
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            Label(isEmpty ? "+ " + text : text, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(isEmpty ? Color.secondary.opacity(0.7) : tint)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(isEmpty ? (hovering ? 0.08 : 0) : (hovering ? 0.18 : 0.1))))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(isEmpty ? 0.3 : 0), style: StrokeStyle(lineWidth: 1, dash: [3])))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .popover(isPresented: $open, arrowEdge: .bottom) { popup { open = false }.padding(12) }
    }
}

/// Priority, effort, due date, snooze and tags of a task as chips (task-properties T4).
struct TaskPropertyRow: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    @Environment(Clock.self) private var clock
    let task: TaskItem
    @Binding var tags: [String]
    @Binding var pendingTag: String

    var body: some View {
        FlowLayout(spacing: 8) {
            priorityChip
            effortChip
            dueChip
            snoozeChip
            TagField(tags: $tags, input: $pendingTag)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func send(_ c: Command) { Task { await app.send(c) } }

    // MARK: Priority

    private var priorityChip: some View {
        PropertyChip(symbol: task.priority.symbol ?? "flag", text: task.priority == .none ? "Priority" : task.priority.label,
                     tint: task.priority.tint, isEmpty: task.priority == .none, help: "Priority (keys 0–4 in the popover)") { close in
            PriorityPicker(current: task.priority) { p in send(.updateTask(id: task.id, TaskPatch(priority: p))); close() }
        }
    }

    // MARK: Effort

    private var effortChip: some View {
        let dayLength = planning.hours.minutesPerDay
        let left = task.remaining(sizes: planning.sizes, dayMinutes: dayLength)
        let progressed = task.workedMinutes != 0 || task.hasEstimatedParts
        let text: String = {
            guard let effort = task.effort else { return task.hasEstimatedParts ? "\(formatEffort(Double(left ?? 0), dayLength: dayLength)) left" : "Effort" }
            guard progressed, let left else { return effort.label }
            return "\(effort.label) · \(formatEffort(Double(left), dayLength: dayLength)) left"
        }()
        return PropertyChip(symbol: "gauge.with.dots.needle.33percent", text: text, isEmpty: task.effort == nil && !task.hasEstimatedParts,
                            help: "Effort: how much work this is (sizes in Settings → Planning)") { close in
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Effort.allCases, id: \.self) { e in
                    popoverRow("\(e.label) · \(formatEffort(Double(planning.sizes[e]), dayLength: dayLength))", selected: task.effort == e) {
                        send(.updateTask(id: task.id, TaskPatch(effort: .some(e)))); close()
                    }
                }
                Divider().padding(.vertical, 4)
                popoverRow("None", selected: task.effort == nil) { send(.updateTask(id: task.id, TaskPatch(effort: .some(nil)))); close() }
                if task.effort != nil, !task.hasEstimatedParts {
                    Divider().padding(.vertical, 4)
                    RemainingEditor(task: task, onDone: close)
                }
            }
            .frame(width: 220)
        }
    }

    // MARK: Due date

    private var dueChip: some View {
        let overdue = task.due.flatMap { LocalDay($0.day) }.map { $0 < clock.today } ?? false
        return PropertyChip(symbol: "calendar", text: task.due.map(Self.shortDue) ?? "Due", tint: overdue ? .red : .primary,
                            isEmpty: task.due == nil, help: "Due date") { close in
            DuePicker(task: task, today: clock.today) { due in send(.updateTask(id: task.id, TaskPatch(due: .some(due)))); close() }
        }
    }

    /// "Fri 30 Oct", "Fri 30 Oct, 14:00".
    static func shortDue(_ due: Due) -> String {
        guard let day = LocalDay(due.day) else { return due.day }
        return DayView.shortTitle(for: day) + (due.time.map { ", " + $0 } ?? "")
    }

    // MARK: Snooze

    private var snoozeChip: some View {
        let until = task.isSnoozed(today: clock.today) ? task.snoozedUntil.flatMap(LocalDay.init) : nil
        return PropertyChip(symbol: "moon.zzz", text: until.map { "Snoozed until \(DayView.weekday($0))" } ?? "Snooze",
                            tint: .blue, isEmpty: until == nil, help: "Hide the task until a day; its due date stays") { close in
            SnoozePicker(task: task, until: until, today: clock.today, onDone: close)
        }
    }
}

/// A selectable line in a property popover.
@ViewBuilder
func popoverRow(_ title: String, symbol: String? = nil, tint: Color = .primary, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint).frame(width: 16) }
            Text(title)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

/// Urgent … None; 0–4 pick by keyboard (T2).
struct PriorityPicker: View {
    let current: Priority
    let choose: (Priority) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let order: [Priority] = [.urgent, .high, .normal, .low, .none]
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(order.enumerated()), id: \.element) { index, p in
                popoverRow("\(4 - index)  \(p.label)", symbol: p.symbol ?? "circle.dashed", tint: p.tint, selected: p == current) { choose(p) }
            }
        }
        .frame(width: 180)
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let n = Int(press.characters), (0...4).contains(n) else { return .ignored }
            choose(order[4 - n]); return .handled
        }
    }
}

/// Quick picks, typed date words, a calendar, time and removal (T2, T3).
struct DuePicker: View {
    let task: TaskItem
    let today: LocalDay
    let apply: (Due?) -> Void
    @State private var typed = ""
    /// Starts at the current due date, set at creation so only a real pick in the calendar counts as a change.
    @State private var date: Date
    @FocusState private var fieldFocused: Bool

    init(task: TaskItem, today: LocalDay, apply: @escaping (Due?) -> Void) {
        self.task = task; self.today = today; self.apply = apply
        _date = State(initialValue: task.due?.date() ?? today.interval().start)
    }

    var body: some View {
        let parsed = DateWords.parse(typed, today: today)
        VStack(alignment: .leading, spacing: 8) {
            TextField("fri, tomorrow, 3 nov 14:00", text: $typed)
                .textFieldStyle(.roundedBorder).focused($fieldFocused)
                .onSubmit { if let parsed { apply(Due(day: parsed.day.description, time: parsed.time)) } }
            if !typed.isEmpty {
                Text(parsed.map { "→ " + TaskPropertyRow.shortDue(Due(day: $0.day.description, time: $0.time)) } ?? "Not a date")
                    .font(.caption).foregroundStyle(parsed == nil ? .red : .secondary)
            }
            HStack {
                quick("Today", today)
                quick("Tomorrow", today.adding(days: 1))
                quick("Mon", TaskActions.nextMonday(after: today))
                quick("+1 week", today.adding(days: 7))
            }
            DatePicker("", selection: $date, displayedComponents: [.date]).datePickerStyle(.graphical).labelsHidden()
                .onChange(of: date) { _, d in apply(Due(day: LocalDay(date: d).description, time: task.due?.time)) }
            HStack {
                if let due = task.due {
                    if due.time == nil {
                        Button("Add time") { apply(Due(day: due.day, time: "09:00")) }
                    } else {
                        DatePicker("Time", selection: Binding(get: { due.date() ?? Date() }, set: { d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            apply(Due(day: due.day, time: String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)))
                        }), displayedComponents: [.hourAndMinute]).fixedSize()
                        Button("Remove time") { apply(Due(day: due.day)) }
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { apply(nil) }
                }
            }
            .buttonStyle(.borderless)
        }
        .frame(width: 260)
        .onAppear { fieldFocused = true }
    }

    private func quick(_ title: String, _ day: LocalDay) -> some View {
        Button(title) { apply(Due(day: day.description, time: task.due?.time)) }.buttonStyle(.bordered).controlSize(.small)
    }
}

/// Snooze until a day, with the "won't fit anymore" warnings, or wake the task (T2).
struct SnoozePicker: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    @Environment(CalendarModel.self) private var calendars
    let task: TaskItem
    let until: LocalDay?
    let today: LocalDay
    let onDone: () -> Void
    @State private var date = Date()

    var body: some View {
        let base = TaskActions.snoozeBase(for: task, today: today)
        VStack(alignment: .leading, spacing: 4) {
            if let due = task.due.flatMap({ LocalDay($0.day) }) {
                Text("Due \(DayView.shortTitle(for: due)) stays").font(.caption).foregroundStyle(.secondary)
            }
            option(until == nil ? "Tomorrow" : "1 more day", base.adding(days: 1))
            option("Next Monday", TaskActions.nextMonday(after: base))
            HStack {
                DatePicker("", selection: $date, in: today.adding(days: 1).interval().start..., displayedComponents: [.date])
                    .labelsHidden().fixedSize()
                Button("Snooze") { snooze(LocalDay(date: date)) }
            }
            .padding(.top, 4)
            if until != nil {
                Divider().padding(.vertical, 4)
                popoverRow("Wake now", symbol: "sun.max", selected: false) {
                    Task { await app.send(.setStatus(id: task.id, .open)) }; onDone()
                }
            }
        }
        .frame(width: 240)
        .onAppear { date = (until ?? today.adding(days: 1)).interval().start }
    }

    private func option(_ title: String, _ day: LocalDay) -> some View {
        let fits = planning.fits(task, returningOn: day, calendars: calendars)
        return popoverRow(fits == false ? "\(title) – won't fit anymore" : title,
                          symbol: fits == false ? "exclamationmark.triangle" : "moon.zzz", tint: fits == false ? .orange : .blue,
                          selected: false) { snooze(day) }
    }

    private func snooze(_ day: LocalDay) {
        Task { await app.send(.setStatus(id: task.id, .snoozed, snoozedUntil: day.description)) }
        onDone()
    }
}
