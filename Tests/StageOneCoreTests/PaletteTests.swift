import XCTest
@testable import StageOneCore

/// SO-080: the command bar's filtering and selection.
final class PaletteTests: XCTestCase {
    let g = UUID()
    var items: [PaletteItem] {
        [
            PaletteItem(.group, "Build", hint: "⌥1", action: .switchGroup(g)),
            PaletteItem(.scene, "Restore Deep work", action: .restoreScene("Deep work")),
            PaletteItem(.scene, "Save this desk as a scene", hint: "⌘⇧S", action: .saveScene),
            PaletteItem(.arrange, "Arrange: Grid", action: .arrange(.grid)),
            PaletteItem(.window, "Inbox – Mail", hint: "Build", action: .focusWindow(42)),
        ]
    }

    func testEmptyQueryKeepsOrderAndLimit() {
        XCTAssertEqual(Palette.filter(items, query: "").map(\.title), items.map(\.title))
        XCTAssertEqual(Palette.filter(items, query: " ", limit: 2).count, 2)
    }

    func testTitleMatchesRankFirst() {
        XCTAssertEqual(Palette.filter(items, query: "deep").first?.action, .restoreScene("Deep work"))
        XCTAssertEqual(Palette.filter(items, query: "grid").first?.action, .arrange(.grid))
    }

    func testTypeAndHintAlsoMatch() {
        XCTAssertEqual(Palette.filter(items, query: "window").map(\.action), [.focusWindow(42)])
        // A window is found by the group it's in, below the group itself.
        let build = Palette.filter(items, query: "build").map(\.action)
        XCTAssertEqual(build.first, .switchGroup(g))
        XCTAssertTrue(build.contains(.focusWindow(42)))
    }

    func testNoMatch() {
        XCTAssertTrue(Palette.filter(items, query: "zzz").isEmpty)
    }

    func testSelectionStaysInRange() {
        XCTAssertEqual(Palette.move(0, by: -1, count: 5), 0)
        XCTAssertEqual(Palette.move(3, by: 1, count: 5), 4)
        XCTAssertEqual(Palette.move(4, by: 1, count: 5), 4)
        XCTAssertEqual(Palette.move(2, by: 1, count: 0), 0)
    }

    func testRewindTitle() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_762_400_000) // a Thursday
        XCTAssertTrue(Palette.rewindTitle(now.addingTimeInterval(-600), now: now, calendar: cal).hasPrefix("Rewind to "))
        XCTAssertFalse(Palette.rewindTitle(now.addingTimeInterval(-600), now: now, calendar: cal).contains(" ", after: 10))
        XCTAssertEqual(Palette.rewindTitle(now.addingTimeInterval(-3 * 86400), now: now, calendar: cal).split(separator: " ").count, 4)
    }
}

private extension String {
    func contains(_ s: String, after i: Int) -> Bool { dropFirst(i).contains(s) }
}
