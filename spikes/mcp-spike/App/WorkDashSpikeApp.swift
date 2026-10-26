// Spike 3 (foundation-spikes): UI app that registers the agent and talks to it. Throwaway code.
import ServiceManagement
import SwiftUI

@main
struct WorkDashSpikeApp: App {
    init() {
        // Cleanup helper: `open WorkDashSpike.app --args --unregister` removes the login item and quits.
        if CommandLine.arguments.contains("--unregister") {
            let service = SMAppService.agent(plistName: "dev.k15r.workdash.spike-agent.plist")
            do { try service.unregister(); print("UNREGISTERED status=\(service.status.rawValue)") }
            catch { print("UNREGISTER ERROR \(error)") }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("WorkDash MCP spike") { ContentView().frame(minWidth: 460, minHeight: 260) }
    }
}

struct ContentView: View {
    @State private var status = "–"
    @State private var reply = "–"
    let service = SMAppService.agent(plistName: "dev.k15r.workdash.spike-agent.plist")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent status: \(status)").font(.headline)
            HStack {
                Button("Register agent") { register() }
                Button("Unregister") { try? service.unregister(); refresh() }
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            Button("Ping agent over XPC") { ping() }
            Text(reply).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
        .padding()
        .onAppear { register() }
    }

    func refresh() {
        switch service.status {
        case .enabled: status = "enabled"
        case .requiresApproval: status = "requires approval (System Settings → Login Items)"
        case .notRegistered: status = "not registered"
        case .notFound: status = "not found (plist missing in bundle?)"
        @unknown default: status = "unknown"
        }
        print("AGENT STATUS \(status)")
    }

    func register() {
        do { try service.register() } catch { reply = "register error: \(error)" ; print("REGISTER ERROR \(error)") }
        refresh()
    }

    func ping() {
        let c = NSXPCConnection(machServiceName: agentMachServiceName)
        c.remoteObjectInterface = NSXPCInterface(with: AgentXPC.self)
        c.resume()
        let proxy = c.remoteObjectProxyWithErrorHandler { e in
            DispatchQueue.main.async { reply = "XPC error: \(e.localizedDescription)" }
        } as! AgentXPC
        proxy.ping { r in DispatchQueue.main.async { reply = r; c.invalidate() } }
    }
}
