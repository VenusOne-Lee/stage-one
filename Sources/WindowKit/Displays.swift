import AppKit
import CoreGraphics
import StageOneCore

/// Display identity and geometry in the top-left global space.
@MainActor
public enum Displays {
    /// Height of the menu bar display, used to flip AppKit frames.
    public static var primaryHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? NSScreen.screens.first?.frame.height ?? 0
    }

    public static func cgID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable id across reboots and ports: vendor-model-serial, falling back to the display number.
    public static func stableID(of screen: NSScreen) -> String {
        let id = cgID(of: screen)
        let v = CGDisplayVendorNumber(id), m = CGDisplayModelNumber(id), s = CGDisplaySerialNumber(id)
        if v == 0 && m == 0 { return "display-\(id)" }
        return String(format: "%X-%X-%X", v, m, s)
    }

    public static func frame(of screen: NSScreen) -> CGRect {
        CoordinateSpace.flip(screen.frame, primaryHeight: primaryHeight)
    }

    public static func visibleFrame(of screen: NSScreen) -> CGRect {
        CoordinateSpace.flip(screen.visibleFrame, primaryHeight: primaryHeight)
    }

    /// The screen holding most of `rect` (top-left space).
    public static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { frame(of: $0).overlapArea(with: rect) < frame(of: $1).overlapArea(with: rect) }
            .flatMap { frame(of: $0).overlapArea(with: rect) > 0 ? $0 : nil }
            ?? NSScreen.screens.first { frame(of: $0).contains(rect.center) }
    }

    public static func screen(withID id: String) -> NSScreen? {
        NSScreen.screens.first { stableID(of: $0) == id }
    }

    /// Union of all display frames, used to pick the off-screen parking spot.
    public static var union: CGRect {
        NSScreen.screens.map(frame(of:)).reduce(CGRect.null) { $0.union($1) }
    }

    /// Which edge the Dock is on, read from the Dock's preferences.
    public static var dockEdge: ScreenEdge {
        let o = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        return ScreenEdge(rawValue: o) ?? .bottom
    }
}
