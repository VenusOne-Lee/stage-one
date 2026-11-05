import Foundation

/// All frames in Stage One use the global "top-left" coordinate space that the
/// Accessibility API and CGWindowList use: origin at the top-left of the main
/// display, y grows downward.
public enum Edge: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom

    public var isVertical: Bool { self == .left || self == .right }
}

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// Clamp this rect into `bounds`: shrink if larger, then shift inside.
    func clamped(to bounds: CGRect) -> CGRect {
        var r = self
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    /// Area of the intersection with another rect (0 when they don't touch).
    func overlapArea(with other: CGRect) -> CGFloat {
        let i = intersection(other)
        return i.isNull ? 0 : i.width * i.height
    }

    func rounded() -> CGRect {
        CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: width.rounded(), height: height.rounded())
    }

    /// `[x, y, w, h]`, the form scene files use.
    var array: [Double] { [Double(minX), Double(minY), Double(width), Double(height)] }

    init(array a: [Double]) {
        let v = a + Array(repeating: 0, count: max(0, 4 - a.count))
        self.init(x: v[0], y: v[1], width: v[2], height: v[3])
    }
}

/// Convert between AppKit's bottom-left screen space and the top-left global space.
/// `primaryHeight` is the height of the main (menu bar) display.
public enum CoordinateSpace {
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
