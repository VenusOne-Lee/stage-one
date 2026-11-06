import XCTest
@testable import StageOneCore

/// SO-024: searching the strip.
final class StripSearchTests: XCTestCase {
    func testFiltersByGroupNameOrAppKeepingOrder() {
        let groups = [StageGroup(name: "Write"), StageGroup(name: "Mail"), StageGroup(name: "Wired")]
        let apps: [String: [String]] = ["Mail": ["Mail", "Calendar"], "Write": ["Pages"]]
        let filter = { StripSearch.filter(groups, query: $0, apps: { apps[$0.name] ?? [] }).map(\.name) }
        XCTAssertEqual(filter(""), ["Write", "Mail", "Wired"])
        XCTAssertEqual(filter("wr"), ["Write", "Wired"])
        XCTAssertEqual(filter("cal"), ["Mail"])
        XCTAssertEqual(filter("pages"), ["Write"])
        XCTAssertEqual(filter("zzz"), [])
    }
}
