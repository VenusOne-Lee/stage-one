import Foundation

/// SO-074: Wi-Fi rules fire when the network name changes to a new one.
public enum WifiRules {
    /// The network just joined, or nil when nothing new was joined (same network, or disconnected).
    public static func joined(previous: String?, current: String?) -> String? {
        guard let current, !current.isEmpty else { return nil }
        return current == previous ? nil : current
    }

    /// True when any enabled scene rule watches Wi-Fi.
    public static func needed(_ scenes: [StageScene]) -> Bool {
        scenes.contains { $0.rule.map { $0.enabled && $0.type == RuleTrigger.wifi.rawValue } ?? false }
    }
}
