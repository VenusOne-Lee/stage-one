import XCTest
@testable import StageOneCore

/// New windows find their own stage, and closed apps leave no empty groups behind.
final class DeskPlacementTests: XCTestCase {
    private let apps: [UInt32: String] = [1: "dia", 2: "dia", 3: "mail", 4: "calc", 5: "dia", 6: "notes", 7: "mail"]
    private let names = ["dia": "Dia", "mail": "Mail", "calc": "Calculator", "notes": "Notes"]

    private func desk() -> (Desk, StageGroup, StageGroup, StageGroup) {
        var d = Desk()
        let web = d.addGroup(named: "Dia", windowIDs: [1, 2])
        let mail = d.addGroup(named: "Mail", windowIDs: [3])
        let calc = d.addGroup(named: "Calculator", windowIDs: [4])
        d.activeID = web.id
        return (d, web, mail, calc)
    }

    func testGroupGoesAwayWhenItsLastWindowCloses() {
        var (d, _, _, calc) = desk()
        d.sync(liveWindowIDs: [1, 2, 3], apps: apps, names: names)
        XCTAssertNil(d.groups.first { $0.id == calc.id })
        XCTAssertEqual(d.groups.map(\.name), ["Dia", "Mail"])
    }

    func testActiveGroupStaysWhenEmptied() {
        var (d, web, _, _) = desk()
        d.sync(liveWindowIDs: [3, 4], apps: apps, names: names)
        XCTAssertEqual(d.activeID, web.id)
        XCTAssertEqual(d.active?.windowIDs, [])
    }

    func testEmptyGroupMadeByHandIsKept() {
        var (d, _, _, _) = desk()
        let fresh = d.addGroup(named: "New group")
        d.sync(liveWindowIDs: [1, 2, 3, 4], apps: apps, names: names)
        XCTAssertNotNil(d.groups.first { $0.id == fresh.id })
    }

    func testNewWindowOfAppOnStageJoinsStage() {
        var (d, web, _, _) = desk()
        let switchTo = d.sync(liveWindowIDs: [5, 1, 2, 3, 4], apps: apps, names: names, frontApp: "dia")
        XCTAssertNil(switchTo)
        XCTAssertEqual(d.groups.first { $0.id == web.id }?.windowIDs, [5, 1, 2])
    }

    func testOpeningAnotherAppGivesItItsOwnStage() {
        var (d, web, _, _) = desk()
        let switchTo = d.sync(liveWindowIDs: [6, 1, 2, 3, 4], apps: apps, names: names, frontApp: "notes")
        let notes = d.groups.last
        XCTAssertEqual(notes?.name, "Notes")
        XCTAssertEqual(notes?.windowIDs, [6])
        XCTAssertEqual(switchTo, notes?.id)
        XCTAssertEqual(d.activeID, web.id, "the caller switches, with the motion")
        XCTAssertEqual(d.groups.first { $0.id == web.id }?.windowIDs, [1, 2])
    }

    func testNewWindowOfAppInTheStripJoinsItsGroup() {
        var (d, _, mail, _) = desk()
        let switchTo = d.sync(liveWindowIDs: [7, 1, 2, 3, 4], apps: apps, names: names, frontApp: "mail")
        XCTAssertEqual(switchTo, mail.id)
        XCTAssertEqual(d.groups.first { $0.id == mail.id }?.windowIDs, [7, 3])
    }

    func testBackgroundAppWindowStaysOnStage() {
        var (d, web, _, _) = desk()
        let switchTo = d.sync(liveWindowIDs: [6, 1, 2, 3, 4], apps: apps, names: names, frontApp: "dia")
        XCTAssertNil(switchTo)
        XCTAssertEqual(d.groups.first { $0.id == web.id }?.windowIDs, [6, 1, 2])
        XCTAssertEqual(d.groups.count, 3)
    }

    func testEmptiedStageTakesTheNextApp() {
        var (d, web, _, _) = desk()
        d.sync(liveWindowIDs: [3, 4], apps: apps, names: names)
        let switchTo = d.sync(liveWindowIDs: [6, 3, 4], apps: apps, names: names, frontApp: "notes")
        XCTAssertNil(switchTo)
        XCTAssertEqual(d.active?.windowIDs, [6])
        XCTAssertEqual(d.active?.id, web.id)
    }

    func testDropEmptyGroupsKeepsTheStage() {
        var d = Desk()
        let a = d.addGroup(named: "A")
        d.addGroup(named: "B")
        d.addGroup(named: "C", windowIDs: [1])
        d.dropEmptyGroups()
        XCTAssertEqual(d.groups.map(\.name), ["A", "C"])
        XCTAssertEqual(d.activeID, a.id)
    }
}
