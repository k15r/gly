// gly core: model, store, tasks, tags and calendar logic shared by the gly app and agent.
// No AppKit/UIKit here (foundation-spikes D6).

/// Identifiers shared by the app, the agent and the MCP bridge (rename-to-gly R1).
public enum GlyIDs {
    public static let teamID = "DB33H6YGK7"
    public static let appGroup = "DB33H6YGK7.dev.k15r.gly"
    public static let agentMachService = "DB33H6YGK7.dev.k15r.gly.store-agent"
    public static let agentPlistName = "dev.k15r.gly.store-agent.plist"
    public static let databaseFileName = "gly.sqlite"
    /// Only processes signed by our team may talk over XPC.
    public static let teamCodeRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"DB33H6YGK7\""

    /// The identifiers from before the rename (WorkDash), read once to take over data (rename-to-gly R2).
    public enum Legacy {
        public static let appGroup = "DB33H6YGK7.dev.k15r.workdash"
        public static let databaseFileName = "workdash.sqlite"
    }
}
