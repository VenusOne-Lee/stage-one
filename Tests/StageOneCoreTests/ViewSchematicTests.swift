import XCTest
@testable import StageOneCore

/// SO-036: the View popover's schematic and presets.
final class ViewSchematicTests: XCTestCase {
    func testNeverOverlapKeepsWindowsOffTheStrip() {
        let d = ViewSchematic.drawing(strip: .left, dock: .left, mode: .reserve, size: .full)
        XCTAssertEqual(d.strip.minX, d.dock.maxX, "the strip sits just inside the Dock")
        XCTAssertFalse(d.windowSpace.intersects(d.strip))
        XCTAssertFalse(d.windowSpace.intersects(d.dock))
    }

    func testCanOverlapLetsWindowsUseTheLane() {
        let d = ViewSchematic.drawing(strip: .bottom, dock: .bottom, mode: .overlap, size: .compact)
        XCTAssertTrue(d.windowSpace.contains(d.strip))
        XCTAssertLessThanOrEqual(d.strip.maxY, d.dock.minY)
    }

    func testPresets() {
        XCTAssertEqual(ViewSchematic.applesWay(dock: .left).strip, .right)
        XCTAssertEqual(ViewSchematic.applesWay(dock: .bottom).strip, .left)
        XCTAssertEqual(ViewSchematic.applesWay(dock: .right).mode, .overlap)
        XCTAssertEqual(ViewSchematic.stageOneWay.mode, .reserve)
        XCTAssertFalse(ViewSchematic.isApple(allowed: "strip", value: "top", dock: .bottom))
        XCTAssertFalse(ViewSchematic.isApple(allowed: "strip", value: "left", dock: .left))
        XCTAssertTrue(ViewSchematic.isApple(allowed: "strip", value: "right", dock: .left))
        XCTAssertFalse(ViewSchematic.isApple(allowed: "mode", value: "reserve", dock: .left))
    }
}
