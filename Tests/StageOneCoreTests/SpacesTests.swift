import XCTest
@testable import StageOneCore

/// SO-014: full screen windows and Spaces.
final class SpacesTests: XCTestCase {
    func testSyncKeepsWindowsThatAreAliveElsewhere() {
        var d = Desk()
        let g = d.addGroup(named: "Write", windowIDs: [1, 2, 3])
        // 2 is on another Space (alive but not visible), 3 was closed.
        d.sync(liveWindowIDs: [1], aliveIDs: [2])
        XCTAssertEqual(d.groups.first { $0.id == g.id }?.windowIDs, [1, 2])
    }

    func testSyncAddsAliveOnlyWindowsNowhere() {
        var d = Desk()
        d.addGroup(named: "Write", windowIDs: [1])
        d.sync(liveWindowIDs: [1], aliveIDs: [9])
        XCTAssertFalse(d.groups.flatMap(\.windowIDs).contains(9), "windows we can't see aren't added to the stage")
    }

    func testSwitchingSpacesKeepsEachDesk() {
        var spaces = SpaceDesks()
        var a = Desk(); a.addGroup(named: "Code", windowIDs: [1, 2])
        let b = spaces.switchSpace(current: a, from: "A", to: "B")
        XCTAssertTrue(b.groups.isEmpty, "a new Space starts empty")
        var b2 = b; b2.addGroup(named: "Mail", windowIDs: [5])
        let back = spaces.switchSpace(current: b2, from: "B", to: "A")
        XCTAssertEqual(back, a)
        XCTAssertEqual(spaces.desks["B"], b2)
        XCTAssertNil(spaces.desks["A"], "the showing Space's desk lives with the caller")
    }

    func testReleaseMovesWindowOutOfOtherSpaces() {
        var other = Desk(); other.addGroup(named: "Code", windowIDs: [1, 2])
        var spaces = SpaceDesks(desks: ["A": other])
        spaces.release([2])
        XCTAssertEqual(spaces.desks["A"]?.groups.first?.windowIDs, [1])
    }

    func testPruneDropsClosedWindowsAndEmptySpaces() {
        var a = Desk(); a.addGroup(named: "Code", windowIDs: [1])
        var b = Desk(); b.addGroup(named: "Mail", windowIDs: [5, 6])
        var spaces = SpaceDesks(desks: ["A": a, "B": b])
        spaces.prune(alive: [6])
        XCTAssertNil(spaces.desks["A"])
        XCTAssertEqual(spaces.desks["B"]?.groups.first?.windowIDs, [6])
    }

    func testMergeIntoSharedSet() {
        var current = Desk(); current.addGroup(named: "Code", windowIDs: [1])
        var other = Desk()
        other.addGroup(named: "Mail", windowIDs: [5])
        other.addGroup(named: "Dup", windowIDs: [1])
        other.addGroup(named: "Empty")
        var spaces = SpaceDesks(desks: ["B": other])
        let merged = spaces.merge(into: current)
        XCTAssertEqual(merged.groups.map(\.name), ["Code", "Mail"])
        XCTAssertEqual(merged.activeID, current.activeID)
        XCTAssertTrue(spaces.desks.isEmpty)
    }
}

extension SpacesTests {
    func testSplitSendsWindowsToTheirSpaces() {
        var d = Desk()
        let code = d.addGroup(named: "Code", windowIDs: [1, 2])
        let mail = d.addGroup(named: "Mail", windowIDs: [5])
        d.addGroup(named: "Empty")
        var spaces = SpaceDesks()
        let space = ["1": "A", "2": "B", "5": "B"]
        let here = spaces.split(d, current: "A", spaceOf: { space[String($0)] })
        XCTAssertEqual(here.groups.map(\.name), ["Code", "Empty"])
        XCTAssertEqual(here.groups.first?.windowIDs, [1])
        XCTAssertEqual(here.activeID, code.id)
        let b = spaces.desks["B"]
        XCTAssertEqual(b?.groups.map(\.name), ["Code", "Mail"])
        XCTAssertEqual(b?.groups.first { $0.id == mail.id }?.windowIDs, [5])
        XCTAssertEqual(b?.activeID, code.id, "the group on stage stays on stage on every Space")
    }
}
