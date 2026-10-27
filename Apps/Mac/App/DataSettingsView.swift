import SwiftUI
import WorkDashCore

/// Settings → Data: erase all data for good (settings stay). Two confirmations: the button, then the alert.
struct DataSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigation.self) private var nav
    @State private var confirming = false
    @State private var done = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Erase all data").font(.headline)
                    Text("Removes all tasks, pages, tags and tag descriptions, appointment overrides, the trash and the change history. Settings (working hours, effort sizes, calendars, agent access) stay. This can't be undone, and no copy is kept.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Erase All Data…", role: .destructive) { confirming = true }
                            .disabled(!app.canWrite)
                        if done { Label("All data erased", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .alert("Erase all WorkDash data?", isPresented: $confirming) {
            Button("Erase All Data", role: .destructive) {
                Task {
                    guard case .ok = await app.send(.eraseAllData) else { return }
                    nav.go(.day)
                    done = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything you and your agents created is removed for good. Settings stay.")
        }
    }
}
