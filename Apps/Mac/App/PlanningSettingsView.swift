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
                ForEach(Effort.allCases, id: \.self) { e in
                    LabeledContent(e.label) {
                        HStack(spacing: 8) {
                            DurationField(minutes: Binding(get: { planning.sizes[e] }, set: { planning.setEffortMinutes(max(5, $0), for: e) }),
                                          dayLength: planning.hours.minutesPerDay)
                            Button("Default") { planning.setEffortMinutes(nil, for: e) }.buttonStyle(.borderless)
                        }
                    }
                }
                Text("Working time a task of each size roughly needs. 1 d = one working day (\(formatMinutes(Double(planning.hours.minutesPerDay)))). L and XL follow the working day until you change them.")
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

    /// Days · hours · minutes, where a day is one working day.
    struct DurationField: View {
        @Binding var minutes: Int
        let dayLength: Int

        var body: some View {
            let day = max(60, dayLength)
            let d = minutes / day, h = (minutes % day) / 60, m = minutes % 60
            HStack(spacing: 4) {
                part(d, "d") { minutes = $0 * day + h * 60 + m }
                part(h, "h") { minutes = d * day + $0 * 60 + m }
                part(m, "m") { minutes = d * day + h * 60 + $0 }
            }
        }

        private func part(_ value: Int, _ unit: String, set: @escaping (Int) -> Void) -> some View {
            HStack(spacing: 2) {
                TextField("", value: Binding(get: { value }, set: { set(max(0, $0)) }), format: .number)
                    .frame(width: 36).multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
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
