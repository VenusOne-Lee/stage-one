import XCTest
@testable import StageOneCore

/// SO-056: multi-display scenes fold onto one display.
final class DisplayFoldTests: XCTestCase {
    let builtIn = StageScene.Display(id: "610-A044-0", frame: [0, 0, 1512, 982], strip: .left, dock: .bottom,
                                     mode: .reserve, size: .full, usable: [204, 33, 1308, 880])
    let external = StageScene.Display(id: "1E6D-5B11-1", frame: [1512, -200, 2560, 1440], strip: .left, dock: .bottom,
                                      mode: .reserve, size: .full, usable: [1716, -175, 2356, 1415])

    func testFindsTheWindowsDisplay() {
        XCTAssertEqual(DisplayFold.display(of: CGRect(x: 2000, y: 100, width: 800, height: 600), in: [builtIn, external])?.id, external.id)
        XCTAssertEqual(DisplayFold.display(of: CGRect(x: 300, y: 100, width: 800, height: 600), in: [builtIn, external])?.id, builtIn.id)
        XCTAssertNil(DisplayFold.display(of: CGRect(x: -5000, y: 0, width: 10, height: 10), in: [builtIn, external]))
    }

    func testFoldKeepsSizeAndRelativePlace() {
        let old = CGRect(x: 1716, y: -175, width: 2356, height: 1415)
        let new = CGRect(x: 204, y: 33, width: 1308, height: 880)
        // Top left stays top left, same size.
        let a = DisplayFold.fold(CGRect(x: 1716, y: -175, width: 800, height: 600), from: old, to: new)
        XCTAssertEqual(a, CGRect(x: 204, y: 33, width: 800, height: 600))
        // Bottom right stays bottom right.
        let b = DisplayFold.fold(CGRect(x: 4072 - 800, y: 1240 - 600, width: 800, height: 600), from: old, to: new)
        XCTAssertEqual(b, CGRect(x: 1512 - 800, y: 913 - 600, width: 800, height: 600))
        // Too big: shrinks to fit.
        let c = DisplayFold.fold(CGRect(x: 1800, y: 0, width: 2000, height: 1200), from: old, to: new)
        XCTAssertEqual(c.size, new.size)
    }

    func testMissing() {
        XCTAssertEqual(DisplayFold.missing([builtIn, external], connected: [builtIn.id]).map(\.id), [external.id])
    }
}
