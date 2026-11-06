import XCTest
@testable import StageOneCore

/// SO-043: new windows on a Free stage cascade.
final class CascadeTests: XCTestCase {
    let area = CGRect(x: 204, y: 25, width: 1236, height: 800)

    func testStepsDownAndRight() {
        let f = Cascade.frame(for: CGSize(width: 600, height: 400), after: CGRect(x: 300, y: 100, width: 700, height: 500), in: area)
        XCTAssertEqual(f, CGRect(x: 328, y: 128, width: 600, height: 400))
    }

    func testWrapsToTheTopLeft() {
        let f = Cascade.frame(for: CGSize(width: 600, height: 400), after: CGRect(x: 900, y: 500, width: 500, height: 300), in: area)
        XCTAssertEqual(f.origin, CGPoint(x: 212, y: 33))
    }

    func testFitsTheArea() {
        let f = Cascade.frame(for: CGSize(width: 3000, height: 2000), after: nil, in: area)
        XCTAssertTrue(area.contains(f))
        XCTAssertEqual(f, area.insetBy(dx: 8, dy: 8))
    }
}
