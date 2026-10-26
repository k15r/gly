import Foundation
import Security

/// Settings shared by the app and the agent through the app-group defaults (design M7).
public struct SharedSettings {
    public let defaults: UserDefaults

    enum Key {
        static let deviceID = "deviceID"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let httpEnabled = "httpEnabled"
        static let httpPort = "httpPort"
        static let httpToken = "httpToken"
        static let httpAllowedOrigins = "httpAllowedOrigins"
    }

    public static let defaultHTTPPort = 47615

    /// The app-group suite (production).
    public static func shared() -> SharedSettings {
        SharedSettings(defaults: UserDefaults(suiteName: WorkDashIDs.appGroup) ?? .standard)
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Stable random device id used in writer names; deliberately not the host name.
    public var deviceID: String {
        if let id = defaults.string(forKey: Key.deviceID) { return id }
        let id = "mac-" + UUID().uuidString.prefix(6).lowercased()
        defaults.set(id, forKey: Key.deviceID)
        return id
    }

    public var hiddenCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Key.hiddenCalendarIDs) }
    }

    public var httpEnabled: Bool {
        get { defaults.bool(forKey: Key.httpEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.httpEnabled) }
    }

    public var httpPort: Int {
        get { let p = defaults.integer(forKey: Key.httpPort); return (1024...65535).contains(p) ? p : Self.defaultHTTPPort }
        nonmutating set { defaults.set(newValue, forKey: Key.httpPort) }
    }

    /// Secret for the local HTTP endpoint; created on first use.
    public var httpToken: String {
        if let t = defaults.string(forKey: Key.httpToken), !t.isEmpty { return t }
        return regenerateHTTPToken()
    }

    @discardableResult
    public func regenerateHTTPToken() -> String {
        let t = Self.makeToken()
        defaults.set(t, forKey: Key.httpToken)
        return t
    }

    public var httpAllowedOrigins: [String] {
        get { defaults.stringArray(forKey: Key.httpAllowedOrigins) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.httpAllowedOrigins) }
    }

    /// One-time copy of values that used to live in the app's standard defaults; only fills missing group keys.
    public func migrate(from old: UserDefaults, oldHiddenKey: String = "hiddenCalendarIDs") {
        if defaults.string(forKey: Key.deviceID) == nil, let id = old.string(forKey: Key.deviceID) {
            defaults.set(id, forKey: Key.deviceID)
        }
        if defaults.object(forKey: Key.hiddenCalendarIDs) == nil, let hidden = old.stringArray(forKey: oldHiddenKey) {
            defaults.set(hidden, forKey: Key.hiddenCalendarIDs)
        }
    }

    /// 32 random bytes, base64url without padding.
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "no secure random bytes")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
