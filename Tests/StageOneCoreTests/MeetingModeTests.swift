import XCTest
@testable import StageOneCore

final class MeetingModeTests: XCTestCase {
    func testDefaultsArePrivate() {
        let l = PrivateList()
        XCTAssertTrue(l.isPrivate(bundleID: "com.apple.mail", title: "Inbox"))
        XCTAssertTrue(l.isPrivate(bundleID: "com.tinyspeck.slackmacgap", title: "general"))
        XCTAssertFalse(l.isPrivate(bundleID: "com.apple.Safari", title: "Docs"))
    }

    func testTitleRules() {
        var l = PrivateList(apps: [])
        l.titles = [.init(pattern: "Bank"), .init(bundleID: "com.apple.Safari", pattern: "*— Private"),
                    .init(pattern: "Payroll*.xlsx")]
        XCTAssertTrue(l.isPrivate(bundleID: "com.google.Chrome", title: "My bank account"))
        XCTAssertTrue(l.isPrivate(bundleID: "com.apple.Safari", title: "Notes — Private"))
        XCTAssertFalse(l.isPrivate(bundleID: "com.google.Chrome", title: "Notes — Private"))
        XCTAssertTrue(l.isPrivate(bundleID: "com.microsoft.Excel", title: "payroll March.xlsx"))
        XCTAssertFalse(l.isPrivate(bundleID: "com.microsoft.Excel", title: "payroll March.xlsx (copy)"))
        XCTAssertFalse(PrivateList.TitleRule(pattern: "  ").matches(bundleID: "x", title: "anything"))
    }

    func testGlob() {
        XCTAssertTrue(PrivateList.glob("*", "anything"))
        XCTAssertTrue(PrivateList.glob("a*c", "abbbc"))
        XCTAssertFalse(PrivateList.glob("a*c", "abbbd"))
        XCTAssertTrue(PrivateList.glob("*mid*", "the middle"))
    }

    func testStateAutoTurnsOffOnlyWhatItTurnedOn() {
        var s = MeetingState()
        XCTAssertEqual(s.sharing(true, autoEnabled: true), true)
        XCTAssertTrue(s.auto)
        XCTAssertEqual(s.sharing(false, autoEnabled: true), false)
        XCTAssertFalse(s.on)

        s.set(true)
        XCTAssertNil(s.sharing(true, autoEnabled: true))
        XCTAssertNil(s.sharing(false, autoEnabled: true))
        XCTAssertTrue(s.on)

        s.set(false)
        XCTAssertNil(s.sharing(true, autoEnabled: false))
        XCTAssertFalse(s.on)
    }

    func testSharingDetector() {
        typealias W = SharingDetector.Window
        XCTAssertTrue(SharingDetector.isSharing(sessionShared: true, windows: []))
        XCTAssertTrue(SharingDetector.isSharing(sessionShared: false, windows: [W(owner: "Google Chrome", title: "meet.google.com is sharing your screen.")]))
        XCTAssertTrue(SharingDetector.isSharing(sessionShared: false, windows: [W(owner: "zoom.us", title: "zoom share toolbar window")]))
        XCTAssertFalse(SharingDetector.isSharing(sessionShared: false, windows: [W(owner: "zoom.us", title: "Zoom Meeting")]))
        XCTAssertFalse(SharingDetector.isSharing(sessionShared: false, windows: [W(owner: "Safari", title: "How to share a file")]))
    }

    func testPrivateListCodable() throws {
        let l = PrivateList(apps: ["a"], titles: [.init(bundleID: "b", pattern: "c*")])
        XCTAssertEqual(try JSONDecoder().decode(PrivateList.self, from: JSONEncoder().encode(l)), l)
    }

    func testEditing() {
        var l = PrivateList(apps: [])
        l.addApp("com.a"); l.addApp("com.a"); l.addApp("")
        XCTAssertEqual(l.apps, ["com.a"])
        l.removeApp("com.a")
        XCTAssertTrue(l.apps.isEmpty)
        XCTAssertTrue(l.addTitle("  Bank ", bundleID: ""))
        XCTAssertFalse(l.addTitle("Bank"))
        XCTAssertFalse(l.addTitle("   "))
        XCTAssertEqual(l.titles, [.init(pattern: "Bank")])
        l.removeTitle(.init(pattern: "Bank"))
        XCTAssertTrue(l.titles.isEmpty)
    }
}
