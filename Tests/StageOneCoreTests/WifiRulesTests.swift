import XCTest
@testable import StageOneCore

final class WifiRulesTests: XCTestCase {
    func testJoined() {
        XCTAssertEqual(WifiRules.joined(previous: nil, current: "Office"), "Office")
        XCTAssertEqual(WifiRules.joined(previous: "Home", current: "Office"), "Office")
        XCTAssertNil(WifiRules.joined(previous: "Office", current: "Office"))
        XCTAssertNil(WifiRules.joined(previous: "Office", current: nil))
        XCTAssertNil(WifiRules.joined(previous: nil, current: ""))
    }

    func testMatchAndNeeded() {
        var s = StageScene(name: "Desk", displays: [], groups: [], active: 0)
        XCTAssertFalse(WifiRules.needed([s]))
        s.rule = .init(type: "wifi", match: "office")
        XCTAssertTrue(WifiRules.needed([s]))
        XCTAssertTrue(RuleEngine.matches(s.rule!, .wifi("Office")))
        XCTAssertFalse(RuleEngine.matches(s.rule!, .wifi("Home")))
    }
}
