import XCTest
@testable import StageOneCore

/// SO-042: keyboard layouts.
final class ShortcutTests: XCTestCase {
    func testDefaultsAndDisplay() {
        XCTAssertEqual(LayoutShortcut.leftHalf.defaultShortcut.display, "⌃⌥←")
        XCTAssertEqual(LayoutShortcut.rightHalf.defaultShortcut.display, "⌃⌥→")
        XCTAssertEqual(LayoutShortcut.fill.defaultShortcut.display, "⌃⌥↑")
        XCTAssertEqual(LayoutShortcut.grid.defaultShortcut.display, "⌃⌥G")
        XCTAssertEqual(LayoutShortcut.commandBar.defaultShortcut.display, "⌃Space")
        XCTAssertFalse(LayoutShortcut.layouts.contains(.commandBar))
        XCTAssertFalse(LayoutShortcut.layouts.contains(.meetingMode))
        XCTAssertEqual(LayoutShortcut.meetingMode.defaultShortcut.display, "⌃⌥M")
        XCTAssertEqual(Set(LayoutShortcut.allCases.map { $0.defaultShortcut }).count, LayoutShortcut.allCases.count)
        XCTAssertEqual(Shortcut(keyCode: 1, modifiers: Shortcut.command | Shortcut.shift).display, "⇧⌘S")
    }

    func testOverridesAndConflicts() {
        let custom = Shortcut(keyCode: 4, modifiers: Shortcut.command | Shortcut.option)
        let overrides = [LayoutShortcut.fill.rawValue: custom]
        XCTAssertEqual(LayoutShortcut.fill.shortcut(in: overrides), custom)
        XCTAssertEqual(LayoutShortcut.grid.shortcut(in: overrides), LayoutShortcut.grid.defaultShortcut)
        XCTAssertEqual(LayoutShortcut.conflict(for: custom, except: .grid, overrides: overrides), .fill)
        XCTAssertNil(LayoutShortcut.conflict(for: custom, except: .fill, overrides: overrides))
    }

    func testNeedsAModifier() {
        XCTAssertFalse(Shortcut(keyCode: 5, modifiers: Shortcut.shift).isUsable)
        XCTAssertTrue(Shortcut(keyCode: 5, modifiers: Shortcut.control).isUsable)
    }
}
