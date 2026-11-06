import Foundation

/// SO-070: what can restore a scene on its own.
public enum RuleTrigger: String, Codable, Sendable, CaseIterable {
    case displayConnected, displayDisconnected, focus, calendar, appLaunched, wifi, time

    public var title: String {
        switch self {
        case .displayConnected: return "A display connects"
        case .displayDisconnected: return "A display unplugs"
        case .focus: return "A Focus starts"
        case .calendar: return "A calendar event starts"
        case .appLaunched: return "An app opens"
        case .wifi: return "You join a Wi-Fi network"
        case .time: return "At a time of day"
        }
    }
}

/// Something that happened, which rules are matched against.
public enum RuleEvent: Sendable, Equatable {
    case displayConnected(String)
    case displayDisconnected(String)
    case focus(String)
    case calendar(title: String, calendar: String)
    case appLaunched(String)
    case wifi(String)
    case time(hour: Int, minute: Int)

    public var trigger: RuleTrigger {
        switch self {
        case .displayConnected: return .displayConnected
        case .displayDisconnected: return .displayDisconnected
        case .focus: return .focus
        case .calendar: return .calendar
        case .appLaunched: return .appLaunched
        case .wifi: return .wifi
        case .time: return .time
        }
    }
}

/// One rule run, for the log.
public struct RuleRun: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case ran, skipped, failed }
    public var date: Date
    public var scene: String
    public var trigger: String
    public var outcome: Outcome

    public init(date: Date, scene: String, trigger: String, outcome: Outcome) {
        self.date = date; self.scene = scene; self.trigger = trigger; self.outcome = outcome
    }
}

public enum RuleEngine {
    public static let logLimit = 50
    /// Seconds a rule waits (with a Skip button) before restoring.
    public static let countdown: TimeInterval = 5

    /// True when an enabled rule fires for this event. Empty parameters match anything.
    public static func matches(_ rule: StageScene.Rule, _ event: RuleEvent) -> Bool {
        guard rule.enabled, rule.type == event.trigger.rawValue else { return false }
        func same(_ want: String?, _ got: String) -> Bool {
            guard let want, !want.isEmpty else { return true }
            return want.caseInsensitiveCompare(got) == .orderedSame
        }
        switch event {
        case .displayConnected(let id), .displayDisconnected(let id): return same(rule.display, id)
        case .focus(let name): return same(rule.match, name)
        case .calendar(let title, let calendar):
            guard let k = rule.match, !k.isEmpty else { return true }
            return title.localizedCaseInsensitiveContains(k) || calendar.caseInsensitiveCompare(k) == .orderedSame
        case .appLaunched(let bundle): return same(rule.app, bundle)
        case .wifi(let name): return same(rule.match, name)
        case .time(let h, let m):
            guard let t = rule.time.flatMap(parseTime) else { return false }
            return t.hour == h && t.minute == m
        }
    }

    /// The first scene whose rule fires. One event restores at most one scene.
    public static func scene(for event: RuleEvent, in scenes: [StageScene]) -> StageScene? {
        scenes.first { $0.rule.map { matches($0, event) } ?? false }
    }

    /// Adds a run, keeping the newest 50.
    public static func append(_ run: RuleRun, to log: inout [RuleRun]) {
        log.insert(run, at: 0)
        if log.count > logLimit { log.removeLast(log.count - logLimit) }
    }

    /// "09:30" → (9, 30).
    public static func parseTime(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}
