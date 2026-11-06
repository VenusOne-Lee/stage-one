import Foundation

/// SO-073: which calendar events have just started, so each one fires its rule once.
public enum CalendarRules {
    /// An event as the watcher sees it. `id` is stable per occurrence (event id plus start).
    public struct Event: Sendable, Equatable {
        public var id: String
        public var title: String
        public var calendar: String
        public var start: Date
        public var allDay: Bool

        public init(id: String, title: String, calendar: String, start: Date, allDay: Bool = false) {
            self.id = id; self.title = title; self.calendar = calendar; self.start = start; self.allDay = allDay
        }
    }

    /// How late a start may be noticed and still count (a sleeping Mac, a coarse timer).
    public static let grace: TimeInterval = 120

    /// Events that started in the last `grace` seconds and haven't fired yet, earliest first.
    /// All-day events never fire: they would restore a scene at midnight.
    public static func started(_ events: [Event], now: Date, fired: Set<String>) -> [Event] {
        events
            .filter { !$0.allDay && !fired.contains($0.id) && $0.start <= now && now.timeIntervalSince($0.start) <= grace }
            .sorted { $0.start < $1.start }
    }

    /// Forgets fired ids older than a day, so the set stays small.
    public static func prune(_ fired: [String: Date], now: Date) -> [String: Date] {
        fired.filter { now.timeIntervalSince($0.value) < 86_400 }
    }

    /// True when any enabled scene rule watches the calendar.
    public static func needed(_ scenes: [StageScene]) -> Bool {
        scenes.contains { $0.rule.map { $0.enabled && $0.type == RuleTrigger.calendar.rawValue } ?? false }
    }
}
