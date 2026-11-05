import Foundation

/// Keeps windows out of the strip's lane (SO-031).
public enum LaneGuard {
    /// Returns the corrected frame if `frame` intrudes into the lane, or nil if it is fine.
    /// The window is moved out first; if it is too big for the usable area it is shrunk,
    /// but never below `minSize`.
    public static func correction(for frame: CGRect, in layout: ScreenLayout,
                                  minSize: CGSize = .zero, tolerance: CGFloat = 1) -> CGRect? {
        guard layout.mode == .reserve else { return nil }
        let lane = layout.lane.insetBy(dx: tolerance, dy: tolerance)
        guard frame.intersects(lane) else { return nil }
        // Only care about windows that are mostly on this display.
        guard frame.overlapArea(with: layout.frame) > 0 else { return nil }
        let usable = layout.usableFrame
        var target = frame
        target.size.width = max(min(frame.width, usable.width), minSize.width)
        target.size.height = max(min(frame.height, usable.height), minSize.height)
        target = target.clamped(to: usable)
        // If minSize forces the window to stay wider than the usable area, keep it hugging the far side.
        if target.width > usable.width {
            switch layout.stripEdge {
            case .left: target.origin.x = usable.minX
            case .right: target.origin.x = usable.maxX - target.width
            default: break
            }
        }
        if target.height > usable.height {
            switch layout.stripEdge {
            case .top: target.origin.y = usable.minY
            case .bottom: target.origin.y = usable.maxY - target.height
            default: break
            }
        }
        target = target.rounded()
        return target == frame.rounded() ? nil : target
    }
}
