import XCTest
@testable import StageOneCore

/// SO-120: export without files, import without clobbering or auto-running.
final class SceneExportTests: XCTestCase {
    func scene(_ name: String) -> StageScene {
        var s = StageScene(name: name, displays: [], groups: [
            .init(name: "A", color: "#ef6f2e", display: nil, layout: .free,
                  windows: [.init(bundleId: "com.microsoft.VSCode", title: "app.tsx", document: "file:///Users/lee/app.tsx",
                                  frame: [0, 0, 100, 100], relaunch: "open -b com.microsoft.VSCode \"/Users/lee/app.tsx\"")])
        ], active: 0)
        s.options.wallpaper = "/Users/lee/Pictures/beach.jpg"
        s.rule = .init(type: "time", time: "09:00")
        return s
    }

    func testExportStripsPaths() throws {
        let out = scene("Deep work").strippingDocuments()
        let w = out.groups[0].windows[0]
        XCTAssertNil(w.document)
        XCTAssertEqual(w.relaunch, "open -b com.microsoft.VSCode")
        XCTAssertNil(out.options.wallpaper)
        let json = String(decoding: try out.encoded(), as: UTF8.self)
        XCTAssertFalse(json.contains("/Users/lee"))
    }

    func testImportRenamesAndDisablesRule() {
        let s = scene("Deep work")
        let same = s.preparedForImport(existingNames: ["Mail"])
        XCTAssertEqual(same.name, "Deep work")
        XCTAssertEqual(same.rule?.enabled, false)

        XCTAssertEqual(s.preparedForImport(existingNames: ["deep work"]).name, "Deep work 2")
        XCTAssertEqual(s.preparedForImport(existingNames: ["Deep-Work", "Deep work 2"]).name, "Deep work 3")
    }
}
