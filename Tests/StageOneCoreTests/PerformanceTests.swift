import XCTest
@testable import StageOneCore

/// SO-130 guardrails. Wall-clock bounds are generous (debug builds on shared CI runners)
/// so they only fail on a real regression, such as an accidental O(n²) in the hot path.
final class PerformanceBudgetTests: XCTestCase {
    /// Best of `runs`, in milliseconds.
    private func bestTime(runs: Int = 5, _ body: () -> Void) -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            best = min(best, ms)
        }
        return best
    }

    /// 200 windows over 20 apps, titles like real ones ("(3) Inbox — Mail - Profile").
    private func desk(windows: Int = 200, apps: Int = 20) -> (saved: [StageScene.Window], live: [WindowSnapshot]) {
        var saved: [StageScene.Window] = []
        var live: [WindowSnapshot] = []
        for i in 0..<windows {
            let app = "com.example.app\(i % apps)"
            let title = "(\(i % 7)) Document \(i) — Project \(i / apps) - App \(i % apps)"
            let frame = CGRect(x: Double(i % 10) * 40, y: Double(i % 7) * 30, width: 800 + Double(i % 5) * 10, height: 600)
            let snap = WindowSnapshot(windowID: UInt32(1000 + i), pid: Int32(100 + i % apps), bundleID: app,
                                      appName: "App \(i % apps)", title: title, document: nil, frame: frame, displayID: "d")
            live.append(snap)
            var s = StageScene.Window(snap)
            s.title = "Document \(i) — Project \(i / apps) - App \(i % apps)"
            saved.append(s)
        }
        return (saved, live.reversed())
    }

    func testIdentityMatcherOver200WindowsUnder50ms() {
        let (saved, live) = desk()
        var result: IdentityMatcher.Result?
        let ms = bestTime { result = IdentityMatcher.match(saved: saved, live: live) }
        XCTAssertLessThan(ms, 50, "IdentityMatcher.match over 200 windows took \(ms)ms")
        XCTAssertEqual(result?.matches.count, 200)
        // Every saved window found its own live window.
        for m in result?.matches ?? [] {
            XCTAssertEqual(m.windowID, UInt32(1000 + m.savedIndex))
        }
    }

    func testGridOf50Under5ms() {
        var frames: [CGRect]?
        let area = CGRect(x: 0, y: 25, width: 2560, height: 1415)
        let ms = bestTime { frames = LayoutEngine.frames(for: .grid, count: 50, in: area) }
        XCTAssertLessThan(ms, 5, "Grid of 50 took \(ms)ms")
        XCTAssertEqual(frames?.count, 50)
        for f in frames ?? [] { XCTAssertTrue(area.contains(f), "\(f) outside \(area)") }
    }

    func testEveryLayoutOf50Under5ms() {
        let area = CGRect(x: 0, y: 25, width: 2560, height: 1415)
        for kind in LayoutKind.allCases where kind != .free {
            let ms = bestTime { _ = LayoutEngine.frames(for: kind, count: 50, in: area) }
            XCTAssertLessThan(ms, 5, "\(kind) of 50 took \(ms)ms")
        }
    }
}
