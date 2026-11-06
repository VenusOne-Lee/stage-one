import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// SO-036: the View popover's mini schematic and its two presets.
public enum ViewSchematic {
    /// A made-up 16:10 display used for the drawing.
    public static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let menuBar: CGFloat = 25
    static let dock: CGFloat = 64

    public struct Drawing: Equatable, Sendable {
        public var screen: CGRect
        public var dock: CGRect
        public var strip: CGRect
        /// Where windows may go.
        public var windowSpace: CGRect
    }

    /// Strip, Dock and window space for a setting, on the sample display.
    public static func drawing(strip: ScreenEdge, dock: ScreenEdge, mode: OverlapMode, size: StripSize) -> Drawing {
        let s = screen
        var visible = CGRect(x: s.minX, y: s.minY + menuBar, width: s.width, height: s.height - menuBar)
        let dockRect: CGRect
        switch dock {
        case .left:
            dockRect = CGRect(x: s.minX, y: visible.midY - 220, width: self.dock, height: 440)
            visible.origin.x += self.dock; visible.size.width -= self.dock
        case .right:
            dockRect = CGRect(x: s.maxX - self.dock, y: visible.midY - 220, width: self.dock, height: 440)
            visible.size.width -= self.dock
        case .top, .bottom:
            dockRect = CGRect(x: s.midX - 330, y: s.maxY - self.dock, width: 660, height: self.dock)
            visible.size.height -= self.dock
        }
        let layout = ScreenLayout(displayID: "schematic", frame: s, visibleFrame: visible,
                                  stripEdge: strip, dockEdge: dock, mode: mode, size: size)
        return Drawing(screen: s, dock: dockRect, strip: layout.lane, windowSpace: layout.usableFrame)
    }

    /// "Show Apple's way": the strip opposite a side Dock (left otherwise), windows may cover it.
    public static func applesWay(dock: ScreenEdge) -> (strip: ScreenEdge, mode: OverlapMode, size: StripSize) {
        (dock == .left ? .right : .left, .overlap, .full)
    }

    /// "Stage One way": the strip on the left (inside the Dock if it's there too), never overlapped.
    public static let stageOneWay: (strip: ScreenEdge, mode: OverlapMode, size: StripSize) = (.left, .reserve, .full)

    /// Options Apple's Stage Manager doesn't offer, greyed out while showing Apple's way.
    public static func isApple(allowed key: String, value: String, dock: ScreenEdge) -> Bool {
        switch key {
        case "mode": return value == OverlapMode.overlap.rawValue
        case "size": return value == StripSize.full.rawValue
        case "strip": return value != "top" && value != "bottom" && value != dock.rawValue
        default: return true
        }
    }
}
