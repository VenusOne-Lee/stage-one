import XCTest
@testable import StageOneCore

/// SO-072/SO-090: scenes as App Intents see them.
final class SceneCatalogTests: XCTestCase {
    private func scene(_ name: String, windows: Int, at t: TimeInterval) -> StageScene {
        let w = (0..<windows).map { i in
            StageScene.Window(bundleId: "com.example.app", title: "W\(i)", document: nil, frame: [0, 0, 100, 100])
        }
        return StageScene(name: name, savedAt: Date(timeIntervalSince1970: t), displays: [],
                          groups: [.init(name: "G", color: "#ef6f2e", display: nil, layout: .free, windows: w)], active: 0)
    }

    func testLoadsNewestFirstAndIgnoresOtherFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for s in [scene("Old", windows: 1, at: 10), scene("New", windows: 2, at: 20)] {
            try s.encoded().write(to: dir.appendingPathComponent(s.slug).appendingPathExtension(StageScene.fileExtension))
        }
        try Data("junk".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(SceneCatalog.load(from: dir).map(\.name), ["New", "Old"])
    }

    func testNamedKeepsRequestedOrderAndDropsUnknown() {
        let all = [scene("Deep work", windows: 1, at: 1), scene("Meeting", windows: 1, at: 2)]
        XCTAssertEqual(SceneCatalog.scenes(named: ["Meeting", "Gone", "Deep work"], in: all).map(\.name), ["Meeting", "Deep work"])
    }

    func testSearchIsFuzzyAndEmptyReturnsAll() {
        let all = [scene("Deep work", windows: 1, at: 1), scene("Meeting", windows: 1, at: 2)]
        XCTAssertEqual(SceneCatalog.search("dw", in: all).map(\.name), ["Deep work"])
        XCTAssertEqual(SceneCatalog.search("  ", in: all).count, 2)
    }

    func testCountsWindows() {
        XCTAssertEqual(SceneCatalog.windowCount(scene("A", windows: 3, at: 0)), 3)
    }
}
