import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// SO-136: the floating "drag Stage One here" tile that sits beside System Settings while
/// Accessibility is being allowed. Pure geometry, so it can be tested without a Mac.
/// All rects use the top-left global space (the same one CGWindowList reports).
public enum PermissionGuide {
    /// One row of `CGWindowListCopyWindowInfo`, reduced to what the guide needs.
    /// `owner` is the owning app's bundle id.
    public struct WindowEntry: Sendable, Equatable {
        public var owner: String
        public var layer: Int
        public var bounds: CGRect

        public init(owner: String, layer: Int, bounds: CGRect) {
            self.owner = owner
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// Which side of the Settings window the tile sits on. The arrow points the other way.
    public enum Side: String, Sendable, Equatable {
        case right, left, inside
    }

    public struct Placement: Sendable, Equatable {
        public var frame: CGRect
        public var side: Side
    }

    /// System Settings' bundle id. Window owners are matched by bundle id, so a translated
    /// app name never hides the window.
    public static let settingsOwners: Set<String> = ["com.apple.systempreferences"]

    /// The main System Settings window: a normal-layer window owned by Settings, the largest one
    /// if there are several (sheets and popovers are smaller). Tiny windows are ignored.
    public static func settingsWindow(in entries: [WindowEntry], owners: Set<String> = settingsOwners) -> CGRect? {
        entries
            .filter { owners.contains($0.owner) && $0.layer == 0 && $0.bounds.width >= 300 && $0.bounds.height >= 200 }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?
            .bounds
    }

    /// Where the tile goes: just right of Settings, else just left, else tucked inside its
    /// bottom-right corner. Always kept on `screen` (the visible frame Settings is on).
    /// The tile lines up with the app list, a little below the Settings title bar.
    public static func place(guide size: CGSize, beside settings: CGRect, on screen: CGRect,
                             gap: CGFloat = 14, topInset: CGFloat = 70) -> Placement {
        let y = settings.minY + topInset
        let right = CGRect(x: settings.maxX + gap, y: y, width: size.width, height: size.height)
        if right.maxX <= screen.maxX {
            return Placement(frame: right.clamped(to: screen).rounded(), side: .right)
        }
        let left = CGRect(x: settings.minX - gap - size.width, y: y, width: size.width, height: size.height)
        if left.minX >= screen.minX {
            return Placement(frame: left.clamped(to: screen).rounded(), side: .left)
        }
        let inside = CGRect(x: settings.maxX - size.width - gap, y: settings.maxY - size.height - gap,
                            width: size.width, height: size.height)
        return Placement(frame: inside.clamped(to: screen).rounded(), side: .inside)
    }

    /// The screen (visible frame, top-left space) holding most of the Settings window.
    public static func screen(for settings: CGRect, among screens: [CGRect]) -> CGRect? {
        screens.max { settings.overlapArea(with: $0) < settings.overlapArea(with: $1) }
    }
}
