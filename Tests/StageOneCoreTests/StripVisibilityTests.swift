import XCTest
@testable import StageOneCore

/// SO-032: "Can overlap" hides the strip when a window touches its lane.
final class StripVisibilityTests: XCTestCase {
    let lane = CGRect(x: 0, y: 25, width: 204, height: 800)

    func testReserveAlwaysShows() {
        var v = StripVisibility()
        XCTAssertTrue(v.update(mode: .reserve, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: false, now: 0))
    }

    func testOverlapHidesWhenAWindowTouchesTheLane() {
        var v = StripVisibility()
        XCTAssertTrue(v.update(mode: .overlap, windowsTouchLane: false, pointerAtEdge: false, pointerInLane: false, now: 0))
        XCTAssertFalse(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: false, now: 1))
        // The window leaves the lane: the strip comes back.
        XCTAssertTrue(v.update(mode: .overlap, windowsTouchLane: false, pointerAtEdge: false, pointerInLane: false, now: 2))
    }

    func testEdgeBringsItBackAndItHidesAfterTheDelay() {
        var v = StripVisibility()
        v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: false, now: 0)
        XCTAssertFalse(v.shown)
        // Over the hidden lane but not at the edge: stays hidden.
        XCTAssertFalse(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: true, now: 0.5))
        XCTAssertTrue(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: true, pointerInLane: true, now: 1))
        XCTAssertTrue(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: true, now: 2))
        XCTAssertTrue(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: false, now: 3))
        XCTAssertEqual(v.recheckAt ?? 0, 3.6, accuracy: 0.001)
        XCTAssertTrue(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: false, now: 3.3))
        XCTAssertFalse(v.update(mode: .overlap, windowsTouchLane: true, pointerAtEdge: false, pointerInLane: false, now: 3.7))
    }

    func testGeometry() {
        XCTAssertTrue(StripVisibility.windowsTouch([CGRect(x: 150, y: 100, width: 600, height: 400)], lane: lane))
        XCTAssertFalse(StripVisibility.windowsTouch([CGRect(x: 204, y: 100, width: 600, height: 400)], lane: lane))
        XCTAssertTrue(StripVisibility.pointerAtEdge(CGPoint(x: 2, y: 300), lane: lane, edge: .left))
        XCTAssertFalse(StripVisibility.pointerAtEdge(CGPoint(x: 10, y: 300), lane: lane, edge: .left))
        XCTAssertFalse(StripVisibility.pointerAtEdge(CGPoint(x: 2, y: 10), lane: lane, edge: .left))
        XCTAssertEqual(StripVisibility.hiddenLane(lane, edge: .left).minX, -40)
    }
}
