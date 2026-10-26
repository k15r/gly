// Spike 3 (foundation-spikes): XPC contract between shim/app and the agent. Throwaway code.
import Foundation

let agentMachServiceName = "DB33H6YGK7.dev.k15r.workdash.spike-agent"
/// Only processes signed by our team may talk to the agent.
let teamCodeRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"DB33H6YGK7\""

@objc protocol AgentXPC {
    /// Returns JSON: {"date": ..., "source": "stub"|"store", "events": [...]}
    func getSchedule(_ date: String, reply: @escaping (String) -> Void)
    func ping(reply: @escaping (String) -> Void)
}
