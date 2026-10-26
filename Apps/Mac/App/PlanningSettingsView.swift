import SwiftUI
import WorkDashCore

/// Settings → Planning (specs/daily-planning "Working hours", "Effort sizes", "Work on list").
struct PlanningSettingsView: View {
    @Environment(PlanningModel.self) private var planning

    var body: some View {
        @Bindable var planning = planning
        Form {
            Section("Working hours") {
                LabeledContent("From") { timePicker(Binding(get: { planning.hours.startMinute }, set: { m in
                    if m < planning.hours.endMinute { planning.hours.startMinute = m }
                })) }
                LabeledContent("To") { timePicker(Binding(get: { planning.hours.endMinute }, set: { m in
                    if m > planning.hours.startMinute { planning.hours.endMinute = m }
                })) }
                Text("The same every day. Free time is only counted inside this window.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Effort sizes") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Size").foregroundStyle(.secondary)
                        Text("Days").foregroundStyle(.secondary)
                        Text("Hours").foregroundStyle(.secondary)
                        Text("Minutes").foregroundStyle(.secondary)
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                    .font(.caption)
                    ForEach(Effort.allCases, id: \.self) { e in
                        DurationRow(effort: e,
                                    minutes: Binding(get: { planning.sizes[e] }, set: { planning.setEffortMinutes(max(5, $0), for: e) }),
                                    dayLength: planning.hours.minutesPerDay,
                                    defaultMinutes: EffortSizes.defaults(for: planning.hours)[e],
                                    reset: { planning.setEffortMinutes(nil, for: e) })
                    }
                }
                Text("Working time a task of each size roughly needs. 1 day = one working day (\(formatMinutes(Double(planning.hours.minutesPerDay)))). Unchanged, L is one and XL three working days, so they follow your working hours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Work on") {
                Picker("Look ahead", selection: $planning.horizon) {
                    ForEach([3, 5, 7, 14], id: \.self) { Text("\($0) days").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 560)
    }

    /// One size as days · hours · minutes (a day is one working day).
    struct DurationRow: View {
        let effort: Effort
        @Binding var minutes: Int
        let dayLength: Int
        let defaultMinutes: Int
        let reset: () -> Void

        var body: some View {
            let day = max(60, dayLength)
            let d = minutes / day, h = (minutes % day) / 60, m = minutes % 60
            GridRow(alignment: .firstTextBaseline) {
                Text(effort.label).font(.body.monospaced().bold())
                number(d) { minutes = $0 * day + h * 60 + m }
                number(h) { minutes = d * day + min($0, day / 60) * 60 + m }
                number(m) { minutes = d * day + h * 60 + min($0, 59) }
                if minutes != defaultMinutes {
                    Button("Reset", action: reset).buttonStyle(.link).fixedSize()
                        .help("Back to the default (\(formatEffort(Double(defaultMinutes), dayLength: dayLength)))"
                              + (effort >= .l ? ", which follows the working day" : ""))
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
        }

        private func number(_ value: Int, set: @escaping (Int) -> Void) -> some View {
            TextField("", value: Binding(get: { value }, set: { set(max(0, $0)) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
        }
    }

    private func timePicker(_ minutes: Binding<Int>) -> some View {
        Picker("", selection: minutes) {
            ForEach(Array(stride(from: 0, through: 24 * 60, by: 30)), id: \.self) { m in
                Text(String(format: "%02d:%02d", m / 60, m % 60)).tag(m)
            }
        }
        .labelsHidden().frame(width: 100)
    }
}
