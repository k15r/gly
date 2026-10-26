// WorkDashCore: model, store, tasks, tags and calendar logic shared by the WorkDash app and agent.
// No AppKit/UIKit here (foundation-spikes D6).

/// Identifiers shared by the app, the agent and (later) other targets.
public enum WorkDashIDs {
    public static let teamID = "DB33H6YGK7"
    public static let appGroup = "DB33H6YGK7.dev.k15r.workdash"
    public static let agentMachService = "DB33H6YGK7.dev.k15r.workdash.store-agent"
    public static let agentPlistName = "dev.k15r.workdash.store-agent.plist"
    public static let databaseFileName = "workdash.sqlite"
    /// Only processes signed by our team may talk over XPC.
    public static let teamCodeRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"DB33H6YGK7\""
}
