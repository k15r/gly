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
                        Stepper(value: Binding(get: { planning.sizes[e] }, set: { planning.setEffortMinutes($0, for: e) }),
                                in: 15...(10 * 24 * 60), step: e < .l ? 15 : 60) {
                            Text(formatMinutes(Double(planning.sizes[e]))).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                        Button("Default") { planning.setEffortMinutes(nil, for: e) }.buttonStyle(.borderless)
                    }
                }
                Text("Working time a task of each size roughly needs. L and XL follow the working day until you change them.")
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

    private func timePicker(_ minutes: Binding<Int>) -> some View {
        Picker("", selection: minutes) {
            ForEach(Array(stride(from: 0, through: 24 * 60, by: 30)), id: \.self) { m in
                Text(String(format: "%02d:%02d", m / 60, m % 60)).tag(m)
            }
        }
        .labelsHidden().frame(width: 100)
    }
}
