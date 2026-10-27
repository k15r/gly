import AppKit
import ServiceManagement
import SwiftUI

/// Settings → Capture (quick-capture Q5): shortcut, menu bar icon, open at login.
struct CaptureSettingsView: View {
    @Environment(CaptureController.self) private var capture
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var recording = false
    /// Modifiers held while recording ("⌃⇧"), and a hint when a combination never arrived (taken by macOS / another app).
    @State private var held = ""
    @State private var heldSomething = false
    @State private var recordHint: String?
    @State private var monitor: Any?
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Quick capture") {
                LabeledContent("Shortcut") {
                    HStack {
                        Button(recording ? (held.isEmpty ? "Press keys… (esc cancels)" : held + "…") : capture.shortcut.display) { recording ? stop() : record() }
                            .frame(minWidth: 160)
                        if capture.shortcut != .default {
                            Button("Reset") { capture.setShortcut(.default) }
                        }
                    }
                }
                if let recordHint {
                    Text(recordHint).font(.caption).foregroundStyle(.orange)
                }
                if !capture.shortcutAvailable {
                    Text("This shortcut is used by another app or the system – choose a different one.")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Opens the capture panel from any app while gly runs.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onDisappear(perform: stop)
    }

    /// Records the next key combination with at least one of ⌘⌃⌥.
    private func record() {
        recording = true
        recordHint = nil; held = ""; heldSomething = false
        GlobalHotKey.shared.unregister()     // so the current shortcut can be pressed again
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                held = CaptureShortcut(keyCode: 0, modifiers: mods).display.replacingOccurrences(of: CaptureShortcut.keyName(0), with: "")
                if !mods.isEmpty { heldSomething = true }
                // Modifiers released without any key arriving: the system or another app took the combination.
                if mods.isEmpty, heldSomething {
                    recordHint = "macOS or another app uses that combination, so it never reached gly – try another (e.g. ⌃⌥⌘Space)."
                    heldSomething = false
                }
                return event
            }
            if event.keyCode == 53 { stop(); return nil }    // esc
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !mods.intersection([.command, .control, .option]).isEmpty else { return nil }
            capture.setShortcut(CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: mods))
            recordHint = nil
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { capture.setShortcut(capture.shortcut) }   // re-register after recording
        recording = false
        held = ""
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}
