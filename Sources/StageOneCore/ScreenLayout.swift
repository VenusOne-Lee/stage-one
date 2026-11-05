import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How windows treat the strip's lane.
public enum OverlapMode: String, Codable, Sendable, CaseIterable {
    /// Never overlap (default): the lane is reserved like the Dock.
    case reserve
    /// Apple's way: windows may cover the strip, which then hides.
    case overlap
    /// The strip stays hidden until the pointer reaches its edge.
    case autohide
}

/// Previews (tilted thumbnails) or a compact icon rail.
public enum StripSize: String, Codable, Sendable, CaseIterable {
    case full, compact

    /// Thickness of the strip lane in points, measured from the screen edge.
    public var thickness: CGFloat {
        switch self {
        case .full: return 204   // 12px inset + 192px strip, as in the prototype
        case .compact: return 84 // 72px rail + margins
        }
    }
}

/// Placement of the strip on one display, plus the geometry that follows from it.
public struct ScreenLayout: Codable, Sendable, Equatable {
    public var displayID: String
    /// Full display frame (top-left global space).
    public var frame: CGRect
    /// Display frame minus menu bar and Dock.
    public var visibleFrame: CGRect
    public var stripEdge: Edge
    public var dockEdge: Edge
    public var mode: OverlapMode
    public var size: StripSize

    public init(displayID: String, frame: CGRect, visibleFrame: CGRect,
                stripEdge: Edge = .left, dockEdge: Edge = .bottom,
                mode: OverlapMode = .reserve, size: StripSize = .full) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.stripEdge = stripEdge
        self.dockEdge = dockEdge
        self.mode = mode
        self.size = size
    }

    /// The lane the strip occupies. It always sits inside the visible frame, so on
    /// the Dock's edge it sits just inside the Dock.
    public var lane: CGRect {
        let v = visibleFrame
        let t = min(size.thickness, stripEdge.isVertical ? v.width / 3 : v.height / 3)
        switch stripEdge {
        case .left: return CGRect(x: v.minX, y: v.minY, width: t, height: v.height)
        case .right: return CGRect(x: v.maxX - t, y: v.minY, width: t, height: v.height)
        case .top: return CGRect(x: v.minX, y: v.minY, width: v.width, height: t * 0.7)
        case .bottom: return CGRect(x: v.minX, y: v.maxY - t * 0.7, width: v.width, height: t * 0.7)
        }
    }

    /// Where windows may live. In `reserve` mode this excludes the lane.
    public var usableFrame: CGRect {
        guard mode == .reserve else { return visibleFrame }
        let v = visibleFrame, l = lane
        switch stripEdge {
        case .left: return CGRect(x: l.maxX, y: v.minY, width: v.maxX - l.maxX, height: v.height)
        case .right: return CGRect(x: v.minX, y: v.minY, width: l.minX - v.minX, height: v.height)
        case .top: return CGRect(x: v.minX, y: l.maxY, width: v.width, height: v.maxY - l.maxY)
        case .bottom: return CGRect(x: v.minX, y: v.minY, width: v.width, height: l.minY - v.minY)
        }
    }
}
