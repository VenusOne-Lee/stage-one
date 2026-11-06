import XCTest
@testable import StageOneCore

/// SO-055: scene options.
final class SceneOptionsTests: XCTestCase {
    func testOldScenesStillDecode() throws {
        let json = #"{"dnd":true,"meetingMode":false}"#.data(using: .utf8)!
        let o = try JSONDecoder().decode(StageScene.Options.self, from: json)
        XCTAssertTrue(o.dnd)
        XCTAssertFalse(o.hideOthers)
        XCTAssertFalse(o.closeOthers)
        XCTAssertNil(o.wallpaper)
    }

    func testRoundTrip() throws {
        let o = StageScene.Options(dnd: false, meetingMode: true, hideOthers: true, closeOthers: false, wallpaper: "/tmp/dune.jpg")
        let back = try JSONDecoder().decode(StageScene.Options.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(back, o)
        XCTAssertFalse(back.isEmpty)
        XCTAssertTrue(StageScene.Options().isEmpty)
    }

    func testAppsNotInScene() {
        let w = StageScene.Window(bundleId: "com.apple.Safari", title: "x", document: nil, frame: [0, 0, 100, 100])
        let scene = StageScene(name: "Code", displays: [], groups: [.init(name: "A", color: "#ef6f2e", display: nil, layout: .free, windows: [w])], active: 0)
        XCTAssertEqual(scene.appsNotInScene(running: ["com.apple.Safari", "com.apple.Mail"]), ["com.apple.Mail"])
    }
}
