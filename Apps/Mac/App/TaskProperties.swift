import SwiftUI
import GlyCore

/// A compact property: icon and value in a capsule, faded "+ Name" when empty; a click opens its popover
/// (specs/tasks "Task page", task-properties T1).
struct PropertyChip<Popup: View>: View {
    let symbol: String
    let text: String
    var tint: Color = .primary
    var isEmpty = false
    /// The small variant of task rows (item rows show the task page's chips on hover).
    var compact = false
    /// Told when the popover opens and closes (a hover-only chip must stay while its popover is open).
    var onOpenChange: (Bool) -> Void = { _ in }
    let help: String
    @ViewBuilder let popup: (_ close: @escaping () -> Void) -> Popup
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            Label(isEmpty ? "+ " + text : text, systemImage: symbol)
                .modifier(ChipStyle(isEmpty: isEmpty, hovering: hovering, tint: tint, compact: compact))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .popover(isPresented: $open, arrowEdge: .bottom) { popup { open = false }.padding(12) }
        .onChange(of: open) { _, isOpen in onOpenChange(isOpen) }
    }
}

/// The look of every property chip: a capsule in callout size; filled when set (in the tint for colored values such as
/// tags), a dashed outline and faded text when empty (task-properties T1).
struct ChipStyle: ViewModifier {
    var isEmpty = false
    var hovering = false
    var tint: Color = .primary
    /// A colored fill (tags) instead of the neutral grey.
    var tinted = false
    /// The small variant used in task rows (status-colors C3).
    var compact = false

    func body(content: Content) -> some View {
        let fill = tinted ? tint : Color.secondary
        content
            .font(compact ? .caption : .callout)
            .lineLimit(1)
            .foregroundStyle(isEmpty ? Color.secondary.opacity(0.7) : tint)
            .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 1 : 3)
            .background(Capsule().fill(fill.opacity(isEmpty ? (hovering ? 0.08 : 0) : (hovering ? 0.2 : (tinted ? 0.13 : 0.1)))))
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(isEmpty ? 0.3 : 0), style: StrokeStyle(lineWidth: 1, dash: [3])))
            .contentShape(Capsule())
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
            EffortPicker(task: task, onDone: close)
        }
    }

    // MARK: Due date

    private var dueChip: some View {
        let overdue = task.due.flatMap { LocalDay($0.day) }.map { $0 < clock.today } ?? false
        return PropertyChip(symbol: "calendar", text: task.due.map(Self.shortDue) ?? "Due", tint: overdue ? StatusKind.overdue.color : .primary,
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
                            isEmpty: until == nil, help: "Hide the task until a day; its due date stays") { close in
            SnoozePicker(task: task, until: until, today: clock.today, onDone: close)
        }
    }
}

/// Effort sizes with their durations, None, and the remaining stepper when it applies (task chip and row quick action).
struct EffortPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    let task: TaskItem
    let onDone: () -> Void

    var body: some View {
        let dayLength = planning.hours.minutesPerDay
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Effort.allCases, id: \.self) { e in
                popoverRow("\(e.label) · \(formatEffort(Double(planning.sizes[e]), dayLength: dayLength))", selected: task.effort == e) {
                    send(.updateTask(id: task.id, TaskPatch(effort: .some(e)))); onDone()
                }
            }
            Divider().padding(.vertical, 4)
            popoverRow("None", selected: task.effort == nil) { send(.updateTask(id: task.id, TaskPatch(effort: .some(nil)))); onDone() }
            if task.effort != nil, !task.hasEstimatedParts {
                Divider().padding(.vertical, 4)
                RemainingEditor(task: task, onDone: onDone)
            }
        }
        .frame(width: 220)
    }

    private func send(_ c: Command) { Task { await app.send(c) } }
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

/// One layout for the due date and snooze popovers: a caption, quick picks, the calendar, and actions (task-properties T2).
struct DatePopover<Actions: View>: View {
    let caption: String?
    let quickPicks: [(title: String, day: LocalDay, warning: String?)]
    let selected: LocalDay?
    let earliest: LocalDay?
    let pick: (LocalDay) -> Void
    @ViewBuilder let actions: () -> Actions
    @State private var date: Date

    init(caption: String?, quickPicks: [(title: String, day: LocalDay, warning: String?)], selected: LocalDay?, earliest: LocalDay? = nil,
         today: LocalDay, pick: @escaping (LocalDay) -> Void, @ViewBuilder actions: @escaping () -> Actions) {
        self.caption = caption; self.quickPicks = quickPicks; self.selected = selected; self.earliest = earliest
        self.pick = pick; self.actions = actions
        // Set at creation, so only a real click in the calendar counts as a pick.
        _date = State(initialValue: (selected ?? today).interval().start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 6) {
                ForEach(quickPicks, id: \.title) { q in
                    Button { pick(q.day) } label: {
                        if q.warning != nil { Label(q.title, systemImage: "exclamationmark.triangle.fill") } else { Text(q.title) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(q.warning != nil ? .orange : nil)
                    .help(q.warning ?? DayView.title(for: q.day))
                }
            }
            if let warning = quickPicks.compactMap(\.warning).first {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            Group {
                if let earliest {
                    DatePicker("", selection: $date, in: earliest.interval().start..., displayedComponents: [.date])
                } else {
                    DatePicker("", selection: $date, displayedComponents: [.date])
                }
            }
            .datePickerStyle(.graphical).labelsHidden()
            .onChange(of: date) { _, d in pick(LocalDay(date: d)) }
            HStack { actions() }.buttonStyle(.borderless)
        }
        .frame(width: 260)
    }
}

/// Due date: quick picks, the calendar, time and removal (T2).
struct DuePicker: View {
    let task: TaskItem
    let today: LocalDay
    let apply: (Due?) -> Void

    var body: some View {
        DatePopover(caption: nil,
                    quickPicks: [("Today", today, nil), ("Tomorrow", today.adding(days: 1), nil),
                                 ("Mon", TaskActions.nextMonday(after: today), nil), ("+1 week", today.adding(days: 7), nil)],
                    selected: task.due.flatMap { LocalDay($0.day) }, today: today,
                    pick: { apply(Due(day: $0.description, time: task.due?.time)) }) {
            if let due = task.due {
                if due.time == nil {
                    Button("Add time") { apply(Due(day: due.day, time: "09:00")) }
                } else {
                    DatePicker("Time", selection: Binding(get: { due.date() ?? Date() }, set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        apply(Due(day: due.day, time: String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)))
                    }), displayedComponents: [.hourAndMinute]).labelsHidden().fixedSize()
                    Button("Remove time") { apply(Due(day: due.day)) }
                }
                Spacer()
                Button("Remove", role: .destructive) { apply(nil) }
            }
        }
    }
}

/// Snooze: the same layout, quick picks warning when the task won't fit anymore, and "Wake now" (T2).
struct SnoozePicker: View {
    @Environment(AppModel.self) private var app
    @Environment(PlanningModel.self) private var planning
    @Environment(CalendarModel.self) private var calendars
    let task: TaskItem
    let until: LocalDay?
    let today: LocalDay
    let onDone: () -> Void

    var body: some View {
        let base = TaskActions.snoozeBase(for: task, today: today)
        let picks = [(until == nil ? "Tomorrow" : "+1 day", base.adding(days: 1)), ("Mon", TaskActions.nextMonday(after: base)),
                     ("+1 week", base.adding(days: 7))]
        DatePopover(caption: task.due.flatMap { LocalDay($0.day) }.map { "Due \(DayView.shortTitle(for: $0)) stays" },
                    quickPicks: picks.map { ($0.0, $0.1, planning.fits(task, returningOn: $0.1, calendars: calendars) == false
                                             ? "Won't fit anymore after this snooze" : nil) },
                    selected: until, earliest: today.adding(days: 1), today: today, pick: snooze) {
            if until != nil {
                Button("Wake now") { Task { await app.send(.setStatus(id: task.id, .open)) }; onDone() }
            }
        }
    }

    private func snooze(_ day: LocalDay) {
        Task { await app.send(.setStatus(id: task.id, .snoozed, snoozedUntil: day.description)) }
        onDone()
    }
}
