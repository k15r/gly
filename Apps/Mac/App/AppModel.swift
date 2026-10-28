import Foundation
import Observation
import ServiceManagement
import GlyCore

struct UndoNotice: Equatable {
    let id = UUID()
    let redo: Bool
    let label: String
    let changed: Bool
}

/// App-wide state: the agent connection, the read-only store and the writer identity (design L2).
@MainActor
@Observable
final class AppModel {
    enum AgentState: Equatable {
        case unknown
        case ready
        case requiresApproval
        case unavailable(String)
    }

    private(set) var agentState: AgentState = .unknown
    private(set) var store: ReadOnlyStore?
    /// Last error from a command, shown as a dismissible message.
    var lastError: String?
    /// Edit → Show Markdown Source: editors show the raw markdown of every line (live-preview L4). Not persisted.
    var showMarkdownSource = false
    /// Short overlay after a store undo/redo, saying what was reverted.
    private(set) var undoNotice: UndoNotice?

    let writer: String
    let systemWriter: String
    private let client = AgentClient()
    private let service = SMAppService.agent(plistName: GlyIDs.agentPlistName)

    let settings: SharedSettings
    /// Agent-reported state for Settings → Agents, e.g. "calendar: fullAccess".
    private(set) var agentStatus: String?

    init(settings: SharedSettings = .shared()) {
        self.settings = settings
        // First launch after the rename: WorkDash's shared settings before anything reads them (rename-to-gly R2).
        LegacyMigration.takeOverSharedSettings()
        // Settings moved to the app group so the agent shares them (design M7); copy old values once.
        settings.migrate(from: .standard)
        let id = settings.deviceID
        writer = "user@\(id)"
        systemWriter = "system@\(id)"
    }

    var canWrite: Bool { agentState == .ready }

    /// Registers the agent, pings it (which makes it create the database) and opens the store.
    func start() async {
        do {
            if service.status != .enabled { try service.register() }
        } catch {
            // Registration can fail while approval is pending; the status below tells which.
        }
        await refreshAgentState()
        if case .unavailable = agentState, service.status == .enabled {
            // Stale registration (e.g. the app moved, or an old build is registered): re-register once.
            try? await service.unregister()
            try? service.register()
            await refreshAgentState()
        }
    }

    func refreshAgentState() async {
        switch service.status {
        case .requiresApproval:
            agentState = .requiresApproval
            return
        case .notFound:
            agentState = .unavailable("The agent is missing from the app bundle.")
            return
        default: break
        }
        switch await client.perform(.ping, writer: writer) {
        case .ok(let r) where r.message == "pong":
            agentState = .ready
            openStoreIfNeeded()
        case .ok:
            agentState = .unavailable("Unexpected agent answer.")
        case .failure(let f):
            agentState = .unavailable(f.message)
            openStoreIfNeeded()      // an existing database can still be read
        }
    }

    private func openStoreIfNeeded() {
        guard store == nil, let url = try? StoreFactory.defaultDatabaseURL() else { return }
        store = try? ReadOnlyStore(url: url)
    }

    /// Sends a command to the agent as the user. Returns the result; failures are also put into `lastError`.
    @discardableResult
    /// - Parameter quiet: the caller handles failures itself (e.g. a rename conflict that turns into a merge question).
    func send(_ command: Command, asSystem: Bool = false, quiet: Bool = false) async -> CommandResult {
        let result = await client.perform(command, writer: asSystem ? systemWriter : writer)
        if case .failure(let f) = result {
            if f.code == .unavailable { await refreshAgentState() }
            if !asSystem && !quiet { lastError = f.message }
        }
        return result
    }

    /// Undo/redo through the agent, then show what happened in the overlay.
    func undoRedo(_ command: Command) async {
        guard case .ok(let r) = await send(command) else { return }
        let notice = UndoNotice(redo: command == .redo, label: r.message ?? "", changed: r.changed)
        undoNotice = notice
        try? await Task.sleep(for: .seconds(1.6))
        if undoNotice == notice { undoNotice = nil }
    }

    func refreshAgentStatus() async {
        if case .ok(let r) = await send(.agentStatus, asSystem: true) { agentStatus = r.message } else { agentStatus = nil }
    }

    /// Tells the agent to re-read the shared settings (HTTP endpoint).
    func settingsChanged() async { await send(.reloadSettings, asSystem: true) }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    func unregisterAgent() async {
        try? await service.unregister()
        agentState = .unavailable("Agent unregistered (Developer menu).")
    }
}
