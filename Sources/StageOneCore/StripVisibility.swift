import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// SO-032 / SO-033: when the strip hides and comes back, for the "Can overlap" and
/// "Auto-hide" modes. Pure state; the app feeds it the pointer, windows and time.
public struct StripVisibility: Sendable, Equatable {
    /// How far the strip slides toward its edge as it hides.
    public static let slide: CGFloat = 40
    /// How close to the edge the pointer must come to bring the strip back.
    public static let edgeMargin: CGFloat = 4
    /// How long the strip stays after the pointer leaves it.
    public static let hideDelay: Double = 0.6

    public private(set) var shown = true
    /// The time the pointer left the strip; it hides `hideDelay` later.
    public private(set) var leftAt: Double?
    private var hovering = false

    public init() {}

    /// When to look again (the end of the hide delay), or nil.
    public var recheckAt: Double? { leftAt.map { $0 + Self.hideDelay } }

    /// Updates and returns whether the strip shows.
    /// - Parameters:
    ///   - windowsTouchLane: an on-stage window overlaps the strip's lane.
    ///   - pointerAtEdge: the pointer is within `edgeMargin` of the strip's screen edge.
    ///   - pointerInLane: the pointer is over the strip's lane.
    @discardableResult
    public mutating func update(mode: OverlapMode, windowsTouchLane: Bool, pointerAtEdge: Bool,
                                pointerInLane: Bool, now: Double) -> Bool {
        guard mode != .reserve else { return reset() }
        if pointerAtEdge || (shown && pointerInLane) {
            shown = true
            hovering = true
            leftAt = nil
            return shown
        }
        if hovering {
            hovering = false
            leftAt = now
        }
        let wantsHidden = hides(mode: mode, windowsTouchLane: windowsTouchLane)
        guard wantsHidden else { return reset() }
        if let l = leftAt, now - l < Self.hideDelay { return shown }
        leftAt = nil
        shown = false
        return shown
    }

    func hides(mode: OverlapMode, windowsTouchLane: Bool) -> Bool {
        mode == .overlap && windowsTouchLane
    }

    private mutating func reset() -> Bool {
        shown = true
        hovering = false
        leftAt = nil
        return true
    }

    // MARK: Geometry

    /// True when any frame overlaps the lane by more than a hairline.
    public static func windowsTouch(_ frames: [CGRect], lane: CGRect) -> Bool {
        frames.contains { $0.intersects(lane.insetBy(dx: 1, dy: 1)) }
    }

    /// True when the pointer is at the lane's outer edge, within its span.
    public static func pointerAtEdge(_ p: CGPoint, lane: CGRect, edge: ScreenEdge, margin: CGFloat = edgeMargin) -> Bool {
        switch edge {
        case .left: return p.x <= lane.minX + margin && p.y >= lane.minY && p.y <= lane.maxY
        case .right: return p.x >= lane.maxX - margin && p.y >= lane.minY && p.y <= lane.maxY
        case .top: return p.y <= lane.minY + margin && p.x >= lane.minX && p.x <= lane.maxX
        case .bottom: return p.y >= lane.maxY - margin && p.x >= lane.minX && p.x <= lane.maxX
        }
    }

    /// The lane moved `slide` points toward its edge (where the strip sits while hidden).
    public static func hiddenLane(_ lane: CGRect, edge: ScreenEdge) -> CGRect {
        switch edge {
        case .left: return lane.offsetBy(dx: -slide, dy: 0)
        case .right: return lane.offsetBy(dx: slide, dy: 0)
        case .top: return lane.offsetBy(dx: 0, dy: -slide)
        case .bottom: return lane.offsetBy(dx: 0, dy: slide)
        }
    }
}
