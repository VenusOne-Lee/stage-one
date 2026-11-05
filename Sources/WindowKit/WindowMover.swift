import AppKit
import ApplicationServices
import StageOneCore

/// SO-011: move and resize with constraints, optionally animated.
@MainActor
public final class WindowMover {
    public static let shared = WindowMover()

    /// Apps that answer AX slowly; animation falls back to a jump for them.
    public private(set) var slowApps: Set<pid_t> = []
    private var animations: [CGWindowID: Timer] = [:]
    /// Respect the Reduce Motion accessibility setting.
    public var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    public init() {}

    /// Sets a frame and returns the frame the window actually got.
    /// Order matters: size, position, size again, so a window moving onto a smaller
    /// area isn't clamped by its old position (the trick Rectangle uses).
    @discardableResult
    public func setFrame(_ window: TrackedWindow, _ rect: CGRect) -> CGRect {
        cancelAnimation(window.id)
        let target = constrained(rect, for: window)
        let start = CFAbsoluteTimeGetCurrent()
        // Turn off AXEnhancedUserInterface while moving: with it on (set by VoiceOver
        // and some tools) apps animate every AX move, which breaks sequences.
        let app = AXUIElementCreateApplication(window.pid)
        let enhanced = AX.bool(app, "AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }

        AX.setSize(window.element, target.size)
        AX.setPosition(window.element, target.origin)
        AX.setSize(window.element, target.size)
        let got = AX.frame(window.element) ?? target
        if CFAbsoluteTimeGetCurrent() - start > 0.05 { slowApps.insert(window.pid) }
        // Learn a minimum size when the app refused to go smaller.
        if got.width > target.width + 1 { window.learnedMinSize.width = got.width }
        if got.height > target.height + 1 { window.learnedMinSize.height = got.height }
        window.snapshot.frame = got
        return got
    }

    /// Moves without resizing.
    @discardableResult
    public func setPosition(_ window: TrackedWindow, _ p: CGPoint) -> CGRect {
        cancelAnimation(window.id)
        AX.setPosition(window.element, p)
        let got = AX.frame(window.element) ?? CGRect(origin: p, size: window.frame.size)
        window.snapshot.frame = got
        return got
    }

    /// Animated frame change: interpolated setFrame calls at 60fps over `duration`
    /// with the prototype's cubic-bezier(.2,.8,.2,1) ease. Jumps for slow apps or Reduce Motion.
    public func animate(_ window: TrackedWindow, to rect: CGRect, duration: TimeInterval = 0.42,
                        delay: TimeInterval = 0, completion: (@MainActor @Sendable (CGRect) -> Void)? = nil) {
        cancelAnimation(window.id)
        let from = window.liveFrame() ?? window.frame
        if reduceMotion || slowApps.contains(window.pid) || duration <= 0 || from == rect {
            let got = setFrame(window, rect)
            completion?(got)
            return
        }
        let target = constrained(rect, for: window)
        let begin = CFAbsoluteTimeGetCurrent() + delay
        let sizeChanges = abs(from.width - target.width) > 1 || abs(from.height - target.height) > 1
        let id = window.id
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let window else { self.cancelAnimation(id); return }
                let now = CFAbsoluteTimeGetCurrent()
                if now < begin { return }
                let p = min(1, (now - begin) / duration)
                let e = Ease.stage(p)
                let f = CGRect(x: from.minX + (target.minX - from.minX) * e,
                               y: from.minY + (target.minY - from.minY) * e,
                               width: from.width + (target.width - from.width) * e,
                               height: from.height + (target.height - from.height) * e)
                let stepStart = CFAbsoluteTimeGetCurrent()
                if sizeChanges { AX.setSize(window.element, f.size) }
                AX.setPosition(window.element, f.origin)
                if CFAbsoluteTimeGetCurrent() - stepStart > 0.05 {
                    // App can't keep up: finish with a jump.
                    self.slowApps.insert(window.pid)
                    self.cancelAnimation(id)
                    completion?(self.setFrame(window, target))
                    return
                }
                if p >= 1 {
                    self.cancelAnimation(id)
                    completion?(self.setFrame(window, target))
                }
            }
        }
        animations[window.id] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func cancelAnimation(_ id: CGWindowID) {
        animations.removeValue(forKey: id)?.invalidate()
    }

    public var isAnimating: Bool { !animations.isEmpty }

    /// Respects the minimum size we learned and, when the app exposes one, its maximum.
    func constrained(_ rect: CGRect, for window: TrackedWindow) -> CGRect {
        var r = rect
        r.size.width = max(r.width, window.learnedMinSize.width)
        r.size.height = max(r.height, window.learnedMinSize.height)
        if let max = AX.size(window.element, "AXMaxSize") {
            r.size.width = min(r.width, max.width)
            r.size.height = min(r.height, max.height)
        }
        if let min = AX.size(window.element, "AXMinSize") {
            r.size.width = Swift.max(r.width, min.width)
            r.size.height = Swift.max(r.height, min.height)
        }
        return r.rounded()
    }
}

/// cubic-bezier(.2, .8, .2, 1), solved numerically.
public enum Ease {
    public static func stage(_ t: Double) -> Double { bezier(t, 0.2, 0.8, 0.2, 1.0) }

    public static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func cx(_ t: Double) -> Double { 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t }
        func cy(_ t: Double) -> Double { 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if cx(t) < x { lo = t } else { hi = t }
        }
        return cy(t)
    }
}
