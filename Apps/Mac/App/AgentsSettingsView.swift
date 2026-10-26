import AppKit
import SwiftUI
import WorkDashCore

/// Settings → Agents (mcp-server design M8): MCP status, Claude Code registration, the experimental
/// local HTTP endpoint, and recent agent changes.
struct AgentsSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(TasksModel.self) private var tasks

    @State private var httpEnabled = false
    @State private var port = SharedSettings.defaultHTTPPort
    @State private var token = ""
    @State private var origins = ""
    @State private var copied: String?

    private var wdMCPPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/wd-mcp").path }
    private var claudeCommand: String { "claude mcp add --scope user workdash -- \"\(wdMCPPath)\"" }
    private var url: String { "http://127.0.0.1:\(port)/mcp/\(token)" }

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Store agent") { Text(agentText) }
                LabeledContent("Calendar access (agent)") { Text(app.agentStatus?.replacingOccurrences(of: "calendar: ", with: "") ?? "unknown") }
            }

            Section {
                LabeledContent("Command") {
                    HStack(alignment: .top) {
                        Text(claudeCommand).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        copyButton(claudeCommand, id: "claude")
                    }
                }
            } header: { Text("Claude Code") } footer: {
                Text("Run once in Terminal. Run it again if you move WorkDash.app.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Local HTTP endpoint", isOn: $httpEnabled)
                    .onChange(of: httpEnabled) { _, on in app.settings.httpEnabled = on; apply() }
                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number.grouping(.never)).labelsHidden().frame(width: 80)
                        .onSubmit { app.settings.httpPort = port; port = app.settings.httpPort; apply() }
                }
                LabeledContent("URL") {
                    HStack(alignment: .top) {
                        Text(url).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        copyButton(url, id: "url")
                    }
                }
                LabeledContent("Token") {
                    Button("Regenerate") { token = app.settings.regenerateHTTPToken(); apply() }
                }
                LabeledContent("Allowed browser origins") {
                    VStack(alignment: .trailing) {
                        TextEditor(text: $origins).font(.system(.caption, design: .monospaced)).frame(height: 44)
                        Button("Apply") {
                            app.settings.httpAllowedOrigins = origins.split(whereSeparator: \.isNewline)
                                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            apply()
                        }
                    }
                }
            } header: { Text("HTTP (experimental)") } footer: {
                Text("Only reachable from this Mac. Anyone with the URL can read your schedule and change tasks, so treat it like a password. Requests from web pages are refused unless their origin is listed above.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Recent agent changes") {
                if tasks.agentChanges.isEmpty {
                    Text("No changes by agents yet").foregroundStyle(.secondary)
                } else {
                    ForEach(tasks.agentChanges) { change in
                        HStack {
                            Text(change.label).lineLimit(1)
                            Spacer()
                            Text(Self.client(change.writer)).font(.caption).foregroundStyle(.secondary)
                            Text(change.at, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .task {
            httpEnabled = app.settings.httpEnabled
            port = app.settings.httpPort
            token = app.settings.httpToken
            origins = app.settings.httpAllowedOrigins.joined(separator: "\n")
            await app.refreshAgentStatus()
        }
    }

    private var agentText: String {
        switch app.agentState {
        case .ready: "running"
        case .unknown: "checking…"
        case .requiresApproval: "needs approval in Login Items"
        case .unavailable(let reason): "unavailable: \(reason)"
        }
    }

    private func apply() { Task { await app.settingsChanged() } }

    private func copyButton(_ text: String, id: String) -> some View {
        Button(copied == id ? "Copied" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = id
            Task { try? await Task.sleep(for: .seconds(1.5)); if copied == id { copied = nil } }
        }
    }

    /// `agent:claude-code@mac-…` → `claude-code`
    static func client(_ writer: String) -> String {
        String(writer.dropFirst("agent:".count).split(separator: "@").first ?? "")
    }
}
