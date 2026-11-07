import XCTest
@testable import StageOneCore

/// SO-136: the drag tile that sits beside System Settings.
final class PermissionGuideTests: XCTestCase {
    let settingsID = "com.apple.systempreferences"
    let screen = CGRect(x: 0, y: 25, width: 1800, height: 1100)
    let tile = CGSize(width: 300, height: 220)

    func testPicksTheLargestNormalSettingsWindow() {
        let main = CGRect(x: 120, y: 40, width: 800, height: 640)
        let entries: [PermissionGuide.WindowEntry] = [
            .init(owner: "com.apple.Safari", layer: 0, bounds: CGRect(x: 0, y: 0, width: 1500, height: 900)),
            .init(owner: settingsID, layer: 0, bounds: CGRect(x: 300, y: 200, width: 420, height: 260)), // a sheet
            .init(owner: settingsID, layer: 0, bounds: main),
            .init(owner: settingsID, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1800, height: 1100)), // overlay
            .init(owner: settingsID, layer: 0, bounds: CGRect(x: 0, y: 0, width: 40, height: 40)),
        ]
        XCTAssertEqual(PermissionGuide.settingsWindow(in: entries), main)
    }

    func testNoSettingsWindow() {
        let entries: [PermissionGuide.WindowEntry] = [
            .init(owner: "com.apple.finder", layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        XCTAssertNil(PermissionGuide.settingsWindow(in: entries))
    }

    func testSitsRightOfSettingsWhenThereIsRoom() {
        let settings = CGRect(x: 120, y: 40, width: 800, height: 640)
        let p = PermissionGuide.place(guide: tile, beside: settings, on: screen)
        XCTAssertEqual(p.side, .right)
        XCTAssertEqual(p.frame, CGRect(x: 934, y: 110, width: 300, height: 220))
    }

    func testFallsBackToTheLeft() {
        let settings = CGRect(x: 900, y: 40, width: 800, height: 640)
        let p = PermissionGuide.place(guide: tile, beside: settings, on: screen)
        XCTAssertEqual(p.side, .left)
        XCTAssertEqual(p.frame.maxX, 886)
    }

    func testTucksInsideWhenSettingsFillsTheScreen() {
        let settings = CGRect(x: 0, y: 25, width: 1800, height: 1100)
        let p = PermissionGuide.place(guide: tile, beside: settings, on: screen)
        XCTAssertEqual(p.side, .inside)
        XCTAssertTrue(screen.contains(p.frame))
        XCTAssertEqual(p.frame.maxX, 1786)
        XCTAssertEqual(p.frame.maxY, 1111)
    }

    func testStaysOnScreenNearTheBottom() {
        let settings = CGRect(x: 120, y: 1000, width: 800, height: 120)
        let p = PermissionGuide.place(guide: tile, beside: settings, on: screen)
        XCTAssertTrue(screen.contains(p.frame))
    }

    func testPicksTheScreenHoldingMostOfSettings() {
        let a = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let b = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let settings = CGRect(x: 1300, y: 100, width: 800, height: 600)
        XCTAssertEqual(PermissionGuide.screen(for: settings, among: [a, b]), b)
    }
}
