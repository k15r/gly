import SwiftUI
import WorkDashCore

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Calendar list grouped by account with show/hide toggles (specs/calendar-sources "Calendar visibility and colors").
struct CalendarListView: View {
    @Environment(CalendarModel.self) private var calendars

    var body: some View {
        Group {
            if calendars.authorization.canRead {
                List {
                    ForEach(calendars.calendarsBySource, id: \.source) { group in
                        Section(group.source) {
                            ForEach(group.calendars) { c in
                                Toggle(isOn: Binding(get: { calendars.isVisible(c.id) }, set: { calendars.setVisible(c.id, $0) })) {
                                    HStack {
                                        Circle().fill(Color(hex: c.colorHex)).frame(width: 10, height: 10)
                                        Text(c.title)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                NoCalendarAccessView()
            }
        }
        .navigationTitle("Calendars")
    }
}

/// Shown when calendar access is missing (specs/calendar-sources "Calendar access permission").
struct NoCalendarAccessView: View {
    @Environment(CalendarModel.self) private var calendars

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text("No calendar access").font(.headline)
            Text(calendars.authorization == .notDetermined
                 ? "WorkDash will ask for access to show your appointments."
                 : "Allow WorkDash to read your calendars to see appointments here. Tasks keep working without it.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Calendar Privacy Settings") { calendars.openPrivacySettings() }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
