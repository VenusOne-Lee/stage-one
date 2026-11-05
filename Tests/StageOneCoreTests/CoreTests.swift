import XCTest
@testable import StageOneCore

final class ScreenLayoutTests: XCTestCase {
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 800)

    func testLeftLaneReservesUsableArea() {
        let l = ScreenLayout(displayID: "d", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible)
        XCTAssertEqual(l.lane.minX, 0)
        XCTAssertEqual(l.usableFrame.minX, l.lane.maxX)
        XCTAssertEqual(l.usableFrame.maxX, 1440)
    }

    func testOverlapModeUsesWholeVisibleFrame() {
        let l = ScreenLayout(displayID: "d", frame: .zero, visibleFrame: visible, mode: .overlap)
        XCTAssertEqual(l.usableFrame, visible)
    }

    func testStripOnDockEdgeSitsInsideVisibleFrame() {
        let l = ScreenLayout(displayID: "d", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, stripEdge: .bottom, dockEdge: .bottom)
        XCTAssertEqual(l.lane.maxY, visible.maxY)
        XCTAssertEqual(l.usableFrame.maxY, l.lane.minY)
    }
}

final class LaneGuardTests: XCTestCase {
    let layout = ScreenLayout(displayID: "d", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                              visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 800))

    func testWindowInLaneIsMovedOut() {
        let fixed = LaneGuard.correction(for: CGRect(x: 50, y: 100, width: 600, height: 400), in: layout)
        XCTAssertNotNil(fixed)
        XCTAssertGreaterThanOrEqual(fixed!.minX, layout.usableFrame.minX)
        XCTAssertEqual(fixed!.width, 600)
    }

    func testTooWideWindowIsShrunk() {
        let fixed = LaneGuard.correction(for: CGRect(x: 0, y: 25, width: 1440, height: 800), in: layout)!
        XCTAssertEqual(fixed, layout.usableFrame.rounded())
    }

    func testWindowOutsideLaneIsLeftAlone() {
        XCTAssertNil(LaneGuard.correction(for: CGRect(x: 400, y: 100, width: 600, height: 400), in: layout))
    }

    func testMinSizeIsRespected() {
        let fixed = LaneGuard.correction(for: CGRect(x: 0, y: 25, width: 1440, height: 800), in: layout, minSize: CGSize(width: 1400, height: 100))!
        XCTAssertEqual(fixed.width, 1400)
    }
}

final class LayoutTests: XCTestCase {
    let area = CGRect(x: 200, y: 25, width: 1200, height: 800)

    func testHalves() {
        let f = LayoutEngine.frames(for: .halves, count: 2, in: area)!
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f[0].width, f[1].width, accuracy: 1)
        XCTAssertEqual(f[1].minX - f[0].maxX, 8, accuracy: 1)
    }

    func testGridFitsAllWindows() {
        let f = LayoutEngine.frames(for: .grid, count: 5, in: area)!
        XCTAssertEqual(f.count, 5)
        for r in f { XCTAssertTrue(area.contains(r)) }
    }

    func testFocusPutsMainFirst() {
        let f = LayoutEngine.frames(for: .focus, count: 3, in: area)!
        XCTAssertGreaterThan(f[0].width, f[1].width)
        XCTAssertEqual(f[1].minX, f[2].minX)
    }

    func testFreeKeepsFrames() { XCTAssertNil(LayoutEngine.frames(for: .free, count: 3, in: area)) }

    func testSnapZones() {
        XCTAssertEqual(SnapZone.zone(for: CGPoint(x: 201, y: 300), in: area), .leftHalf)
        XCTAssertEqual(SnapZone.zone(for: CGPoint(x: 1399, y: 300), in: area), .rightHalf)
        XCTAssertEqual(SnapZone.zone(for: CGPoint(x: 700, y: 26), in: area), .fill)
        XCTAssertNil(SnapZone.zone(for: CGPoint(x: 700, y: 400), in: area))
    }

    func testLooseLayoutNames() {
        XCTAssertEqual(LayoutKind(loose: "Main + side"), .focus)
        XCTAssertEqual(LayoutKind(loose: "halves"), .halves)
    }
}

final class ReflowTests: XCTestCase {
    func testProportionalRemap() {
        let old = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let new = CGRect(x: 100, y: 0, width: 500, height: 1000)
        let r = Reflow.remap(CGRect(x: 500, y: 0, width: 500, height: 500), from: old, to: new)
        XCTAssertEqual(r, CGRect(x: 350, y: 0, width: 250, height: 500))
    }
}

final class DeskTests: XCTestCase {
    func testSyncAddsNewWindowsToActiveGroupAndDropsClosed() {
        var d = Desk()
        let a = d.addGroup(named: "A", windowIDs: [1, 2])
        d.addGroup(named: "B", windowIDs: [3])
        d.activeID = a.id
        d.sync(liveWindowIDs: [1, 3, 4])
        XCTAssertEqual(d.groups[0].windowIDs, [4, 1])
        XCTAssertEqual(d.groups[1].windowIDs, [3])
    }

    func testMoveWindowBetweenGroups() {
        var d = Desk()
        d.addGroup(named: "A", windowIDs: [1, 2])
        let b = d.addGroup(named: "B", windowIDs: [3])
        d.move(windowID: 1, to: b.id)
        XCTAssertEqual(d.groups[0].windowIDs, [2])
        XCTAssertEqual(d.groups[1].windowIDs, [1, 3])
    }

    func testStripHidesActiveGroup() {
        var d = Desk()
        d.addGroup(named: "A"); d.addGroup(named: "B")
        XCTAssertEqual(d.stripGroups.map(\.name), ["B"])
    }

    func testGroupLookupByIndexAndName() {
        var d = Desk()
        d.addGroup(named: "Inbox"); d.addGroup(named: "Stoepi build")
        XCTAssertEqual(d.group(named: "2")?.name, "Stoepi build")
        XCTAssertEqual(d.group(named: "stoe")?.name, "Stoepi build")
    }

    func testColorsNeverGreen() {
        for c in GroupColor.palette {
            let hex = Int(c.dropFirst(), radix: 16)!
            let r = (hex >> 16) & 0xff, g = (hex >> 8) & 0xff, b = hex & 0xff
            XCTAssertFalse(g > r && g > b, "\(c) reads as green")
        }
    }
}

final class SceneTests: XCTestCase {
    func testRoundTripAndSlug() throws {
        let s = StageScene(name: "Deep build", displays: [], groups: [
            .init(name: "Stoepi build", color: "#ef6f2e", display: nil, layout: .focus,
                  windows: [.init(bundleId: "com.microsoft.VSCode", title: "app.tsx — stoepi", document: "file:///x", frame: [236, 84, 700, 708])])
        ], active: 0)
        let back = try StageScene.decode(try s.encoded())
        XCTAssertEqual(back.name, "Deep build")
        XCTAssertEqual(back.groups[0].windows[0].frame, [236, 84, 700, 708])
        XCTAssertEqual(s.slug, "deep-build")
        XCTAssertNil(s.strippingDocuments().groups[0].windows[0].document)
    }

    func testDecodesBacklogExample() throws {
        let json = """
        { "version": 1, "name": "Deep build", "savedAt": "2026-11-05T21:40:00+02:00",
          "displays": [{ "id": "LG-27UL850", "frame": [0,0,2560,1440], "strip": "left", "dock": "bottom", "mode": "reserve", "size": "full" }],
          "groups": [{ "name": "Stoepi build", "color": "#ef6f2e", "display": "LG-27UL850", "layout": "focus",
            "windows": [{ "bundleId": "com.microsoft.VSCode", "title": "app.tsx — stoepi", "document": "file:///Users/lee/stoepi/src/app.tsx",
                          "frame": [236,84,700,708], "relaunch": "open -a 'Visual Studio Code' ~/stoepi" }] }],
          "active": 0, "rule": { "type": "displayConnected", "display": "LG-27UL850" }, "options": { "dnd": true, "meetingMode": false } }
        """
        let s = try StageScene.decode(Data(json.utf8))
        XCTAssertEqual(s.displays[0].strip, .left)
        XCTAssertEqual(s.rule?.type, "displayConnected")
        XCTAssertTrue(s.options.dnd)
    }
}

final class IdentityTests: XCTestCase {
    func live(_ id: UInt32, _ bundle: String, _ title: String, doc: String? = nil) -> WindowSnapshot {
        WindowSnapshot(windowID: id, pid: 1, bundleID: bundle, appName: "", title: title, document: doc,
                       frame: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: "d")
    }
    func saved(_ bundle: String, _ title: String, doc: String? = nil) -> StageScene.Window {
        .init(bundleId: bundle, title: title, document: doc, frame: [0, 0, 800, 600])
    }

    func testDocumentMatchIsCertain() {
        let r = IdentityMatcher.match(saved: [saved("com.apple.TextEdit", "a", doc: "file:///a.txt")],
                                      live: [live(9, "com.apple.TextEdit", "renamed", doc: "file:///a.txt")])
        XCTAssertEqual(r.matches.first?.windowID, 9)
        XCTAssertEqual(r.matches.first?.confidence, 1)
    }

    func testRenamedTabStillMatchesSingleWindow() {
        let r = IdentityMatcher.match(saved: [saved("com.google.Chrome", "Inbox (3) - Gmail - Google Chrome")],
                                      live: [live(5, "com.google.Chrome", "Inbox (4) - Gmail - Google Chrome")])
        XCTAssertEqual(r.matches.first?.windowID, 5)
    }

    func testMultipleFinderWindowsMatchByTitle() {
        let r = IdentityMatcher.match(
            saved: [saved("com.apple.finder", "Downloads"), saved("com.apple.finder", "stoepi")],
            live: [live(1, "com.apple.finder", "stoepi"), live(2, "com.apple.finder", "Downloads")])
        XCTAssertEqual(r.matches.map(\.windowID), [2, 1])
    }

    func testChromeProfilesDontCrossMatch() {
        let r = IdentityMatcher.match(
            saved: [saved("com.google.Chrome", "Stoepi admin - Google Chrome - Work")],
            live: [live(1, "com.google.Chrome", "YouTube - Google Chrome - Personal"),
                   live(2, "com.google.Chrome", "Stoepi admin - Google Chrome - Work")])
        XCTAssertEqual(r.matches.first?.windowID, 2)
    }

    func testLowConfidenceGoesUnmatched() {
        let r = IdentityMatcher.match(
            saved: [saved("com.apple.finder", "Projects")],
            live: [live(1, "com.apple.finder", "Music"), live(2, "com.apple.finder", "Pictures")])
        XCTAssertTrue(r.matches.isEmpty)
        XCTAssertEqual(r.unmatchedSaved, [0])
    }

    func testDifferentAppsNeverMatch() {
        let r = IdentityMatcher.match(saved: [saved("a", "x")], live: [live(1, "b", "x")])
        XCTAssertTrue(r.matches.isEmpty)
    }
}

final class CommandTests: XCTestCase {
    func testURLScheme() {
        XCTAssertEqual(Command(url: URL(string: "stageone://restore?scene=Deep%20build")!), .restore(scene: "Deep build"))
        XCTAssertEqual(Command(url: URL(string: "stageone://layout?kind=halves")!), .layout(.halves))
        XCTAssertNil(Command(url: URL(string: "https://x")!))
        XCTAssertTrue(Command.restore(scene: "x").isDestructive)
    }

    func testURLSchemeCoversEveryCommand() {
        func c(_ s: String) -> Command? { Command(url: URL(string: s)!) }
        XCTAssertEqual(c("stageone://list"), .list)
        XCTAssertEqual(c("stageone://status"), .status)
        XCTAssertEqual(c("stageone://save?name=Morning"), .save(name: "Morning"))
        XCTAssertEqual(c("stageone://group?index=2"), .group("2"))
        XCTAssertEqual(c("stageone://group?name=Mail"), .group("Mail"))
        XCTAssertEqual(c("stageone://rewind"), .rewind(to: nil))
        XCTAssertEqual(c("stageone://export?scene=Deep&path=/tmp/x.stagescene"), .export(scene: "Deep", path: "/tmp/x.stagescene", includeFiles: false))
        XCTAssertEqual(c("stageone://import?path=/tmp/x.stagescene"), .importScene(path: "/tmp/x.stagescene"))
        XCTAssertEqual(c("stageone://pause"), .pause(true))
        XCTAssertEqual(c("stageone://resume"), .pause(false))
        XCTAssertNil(c("stageone://restore"))
        XCTAssertNil(c("stageone://launch-missiles"))
        XCTAssertFalse(Command.list.isDestructive)
        XCTAssertTrue(Command.export(scene: "a", path: "/b", includeFiles: false).isDestructive)
    }

    func testFuzzy() {
        XCTAssertNotNil(Fuzzy.score("db", in: "Deep build"))
        XCTAssertNil(Fuzzy.score("zz", in: "Deep build"))
        XCTAssertEqual(Fuzzy.rank(["Wind down", "Deep build"], query: "deep", key: { $0 }).first, "Deep build")
    }
}
