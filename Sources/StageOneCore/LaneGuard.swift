import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

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
        // Shift inside the usable area on each axis that fits.
        if target.width <= usable.width {
            target.origin.x = min(max(target.minX, usable.minX), usable.maxX - target.width)
        } else {
            // minSize keeps it wider than the usable area: hug the side away from the strip.
            target.origin.x = layout.stripEdge == .right ? usable.maxX - target.width : usable.minX
        }
        if target.height <= usable.height {
            target.origin.y = min(max(target.minY, usable.minY), usable.maxY - target.height)
        } else {
            target.origin.y = layout.stripEdge == .bottom ? usable.maxY - target.height : usable.minY
        }
        target = target.rounded()
        return target == frame.rounded() ? nil : target
    }
}
