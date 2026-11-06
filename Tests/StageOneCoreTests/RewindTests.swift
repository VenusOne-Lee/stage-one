import XCTest
@testable import StageOneCore

/// SO-060: automatic snapshots.
final class RewindTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testSkipsIdenticalStates() {
        XCTAssertFalse(RewindPolicy.shouldSave("a", latest: "a"))
        XCTAssertTrue(RewindPolicy.shouldSave("b", latest: "a"))
        XCTAssertTrue(RewindPolicy.shouldSave("b", latest: nil))
    }

    func testPrunesOldAndOversized() {
        let day: TimeInterval = 86_400
        let entries = [
            RewindPolicy.Entry(date: now.addingTimeInterval(-8 * day), bytes: 10),       // too old
            RewindPolicy.Entry(date: now.addingTimeInterval(-2 * day), bytes: 60),       // oldest kept, dropped for size
            RewindPolicy.Entry(date: now.addingTimeInterval(-1 * day), bytes: 50),
            RewindPolicy.Entry(date: now, bytes: 40),
        ]
        XCTAssertEqual(RewindPolicy.prune(entries, now: now, maxBytes: 100), [0, 1])
        XCTAssertEqual(RewindPolicy.prune(entries, now: now, maxBytes: 1000), [0])
    }

    func testTarget() {
        let dates = [now.addingTimeInterval(-3600), now.addingTimeInterval(-900), now.addingTimeInterval(-10)]
        XCTAssertEqual(RewindPolicy.target(for: now.addingTimeInterval(-1000), in: dates, now: now), 0)
        XCTAssertEqual(RewindPolicy.target(for: nil, in: dates, now: now), 1)
        XCTAssertNil(RewindPolicy.target(for: now.addingTimeInterval(-7200), in: dates, now: now))
    }

    func testFileNamesRoundTrip() {
        let name = RewindPolicy.fileName(for: now)
        XCTAssertFalse(name.contains(":"))
        XCTAssertEqual(RewindPolicy.date(fromFileName: name), now)
    }
}

/// SO-061: "Since then".
extension RewindTests {
    func testDiff() {
        func w(_ b: String, _ t: String) -> StageScene.Window { .init(bundleId: b, title: t, document: nil, frame: [0, 0, 10, 10]) }
        func scene(_ groups: [(String, [StageScene.Window])]) -> StageScene {
            StageScene(name: "s", displays: [], groups: groups.map { .init(name: $0.0, color: "#ef6f2e", display: nil, layout: .free, windows: $0.1) }, active: 0)
        }
        let then = scene([("Code", [w("com.a", "main.swift"), w("com.b", "Inbox")]), ("Docs", [w("com.c", "Spec")])])
        let now = scene([("Code", [w("com.a", "main.swift"), w("com.d", "Figma")])])
        let d = SnapshotDiff.between(then: then, now: now)
        XCTAssertEqual(d.added, ["Figma"])
        XCTAssertEqual(d.gone.map(\.window.title), ["Inbox", "Spec"])
        XCTAssertEqual(d.gone.map(\.group), ["Code", "Docs"])
        XCTAssertTrue(SnapshotDiff.between(then: now, now: now).isEmpty)
    }
}
