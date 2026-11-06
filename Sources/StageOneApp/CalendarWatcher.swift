import EventKit
import StageOneCore

/// SO-073: posts `.calendar` rule events when an event starts. Only reads the calendar
/// when a scene has a calendar rule and access was given (asked when that rule is saved).
@MainActor
final class CalendarWatcher {
    static let shared = CalendarWatcher()

    private let store = EKEventStore()
    /// Occurrence ids that already fired, with when, so each start fires once.
    private var fired: [String: Date] = [:]

    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks for calendar access the first time a calendar rule is made.
    func requestAccess() async -> Bool {
        if Self.authorized { return true }
        return await withCheckedContinuation { (k: CheckedContinuation<Bool, Never>) in
            store.requestFullAccessToEvents { granted, _ in k.resume(returning: granted) }
        }
    }

    /// Called every minute by the rule clock.
    func check(scenes: [StageScene], now: Date = Date()) {
        guard Self.authorized, CalendarRules.needed(scenes) else { return }
        let from = now.addingTimeInterval(-CalendarRules.grace)
        let predicate = store.predicateForEvents(withStart: from, end: now.addingTimeInterval(1), calendars: nil)
        let events = store.events(matching: predicate).map { e in
            CalendarRules.Event(id: "\(e.calendarItemIdentifier)@\(e.startDate.timeIntervalSince1970)",
                                title: e.title ?? "", calendar: e.calendar?.title ?? "",
                                start: e.startDate, allDay: e.isAllDay)
        }
        fired = CalendarRules.prune(fired, now: now)
        for e in CalendarRules.started(events, now: now, fired: Set(fired.keys)) {
            fired[e.id] = now
            RuleService.shared.post(.calendar(title: e.title, calendar: e.calendar))
        }
    }
}
