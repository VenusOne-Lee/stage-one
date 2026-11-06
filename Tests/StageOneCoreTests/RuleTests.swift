import XCTest
@testable import StageOneCore

/// SO-070: the rule engine.
final class RuleTests: XCTestCase {
    func testMatching() {
        let display = StageScene.Rule(type: "displayConnected", display: "1E6D-5B11-1")
        XCTAssertTrue(RuleEngine.matches(display, .displayConnected("1E6D-5B11-1")))
        XCTAssertFalse(RuleEngine.matches(display, .displayConnected("other")))
        XCTAssertFalse(RuleEngine.matches(display, .displayDisconnected("1E6D-5B11-1")))

        let anyApp = StageScene.Rule(type: "appLaunched")
        XCTAssertTrue(RuleEngine.matches(anyApp, .appLaunched("com.figma.Desktop")))
        let figma = StageScene.Rule(type: "appLaunched", app: "com.figma.Desktop")
        XCTAssertFalse(RuleEngine.matches(figma, .appLaunched("com.apple.Mail")))

        let standup = StageScene.Rule(type: "calendar", match: "standup")
        XCTAssertTrue(RuleEngine.matches(standup, .calendar(title: "Daily Standup", calendar: "Work")))
        XCTAssertFalse(RuleEngine.matches(standup, .calendar(title: "Lunch", calendar: "Home")))

        let nine = StageScene.Rule(type: "time", time: "09:00")
        XCTAssertTrue(RuleEngine.matches(nine, .time(hour: 9, minute: 0)))
        XCTAssertFalse(RuleEngine.matches(nine, .time(hour: 9, minute: 1)))
        XCTAssertFalse(RuleEngine.matches(StageScene.Rule(type: "time"), .time(hour: 9, minute: 0)), "a time rule needs a time")

        var off = display
        off.enabled = false
        XCTAssertFalse(RuleEngine.matches(off, .displayConnected("1E6D-5B11-1")))
    }

    func testOldRulesDecodeEnabled() throws {
        let r = try JSONDecoder().decode(StageScene.Rule.self, from: #"{"type":"focus"}"#.data(using: .utf8)!)
        XCTAssertTrue(r.enabled)
    }

    func testLogKeepsFifty() {
        var log: [RuleRun] = []
        for i in 0..<60 { RuleEngine.append(RuleRun(date: Date(timeIntervalSince1970: Double(i)), scene: "s", trigger: "time", outcome: .ran), to: &log) }
        XCTAssertEqual(log.count, 50)
        XCTAssertEqual(log.first?.date, Date(timeIntervalSince1970: 59))
    }

    func testParseTime() {
        XCTAssertEqual(RuleEngine.parseTime("09:30")?.hour, 9)
        XCTAssertNil(RuleEngine.parseTime("25:00"))
    }
}
