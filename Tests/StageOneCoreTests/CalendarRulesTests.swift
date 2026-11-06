import XCTest
@testable import StageOneCore

final class CalendarRulesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func ev(_ id: String, _ offset: TimeInterval, allDay: Bool = false) -> CalendarRules.Event {
        .init(id: id, title: "Standup", calendar: "Work", start: now.addingTimeInterval(offset), allDay: allDay)
    }

    func testStartedWithinGrace() {
        let got = CalendarRules.started([ev("a", -30), ev("b", 60), ev("c", -600), ev("d", 0)], now: now, fired: [])
        XCTAssertEqual(got.map(\.id), ["a", "d"])
    }

    func testFiredAndAllDaySkipped() {
        let got = CalendarRules.started([ev("a", -30), ev("b", -10, allDay: true)], now: now, fired: ["a"])
        XCTAssertTrue(got.isEmpty)
    }

    func testPrune() {
        let p = CalendarRules.prune(["old": now.addingTimeInterval(-90_000), "new": now.addingTimeInterval(-60)], now: now)
        XCTAssertEqual(Array(p.keys), ["new"])
    }

    func testNeededAndMatch() {
        var s = StageScene(name: "Calls", displays: [], groups: [], active: 0)
        XCTAssertFalse(CalendarRules.needed([s]))
        s.rule = .init(type: "calendar", match: "standup")
        XCTAssertTrue(CalendarRules.needed([s]))
        XCTAssertTrue(RuleEngine.matches(s.rule!, .calendar(title: "Daily Standup", calendar: "Work")))
        XCTAssertFalse(RuleEngine.matches(s.rule!, .calendar(title: "Lunch", calendar: "Home")))
        s.rule?.enabled = false
        XCTAssertFalse(CalendarRules.needed([s]))
    }
}
