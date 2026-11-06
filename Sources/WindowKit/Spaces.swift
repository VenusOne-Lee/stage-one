import CoreGraphics
import Foundation

/// SO-014: which macOS Space is showing, and which Spaces a window is on.
///
/// macOS has no public API for Spaces. These are the long-stable SkyLight calls that yabai,
/// Hammerspoon and AeroSpace's helpers use. They are looked up at runtime, so a macOS that
/// drops one makes Stage One fall back to treating all Spaces as one, never crash.
public enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    nonisolated(unsafe) private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ names: [String], as: T.Type) -> T? {
        for name in names {
            if let h = skyLight, let p = dlsym(h, name) { return unsafeBitCast(p, to: T.self) }
            if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return unsafeBitCast(p, to: T.self) }
        }
        return nil
    }

    nonisolated(unsafe) private static let mainConnection = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnection.self)
    nonisolated(unsafe) private static let activeSpace = symbol(["SLSGetActiveSpace", "CGSGetActiveSpace"], as: ActiveSpace.self)
    nonisolated(unsafe) private static let spaceType = symbol(["SLSSpaceGetType", "CGSSpaceGetType"], as: SpaceType.self)
    nonisolated(unsafe) private static let spacesForWindows = symbol(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], as: SpacesForWindows.self)

    /// False when this macOS doesn't offer the calls; per-Space groups are then unavailable.
    public static var isAvailable: Bool { mainConnection != nil && activeSpace != nil }

    /// The Space showing on the display with the menu bar.
    public static func active() -> UInt64? {
        guard let main = mainConnection, let active = activeSpace else { return nil }
        let id = active(main())
        return id == 0 ? nil : id
    }

    /// True for the Space macOS makes for a native full screen window.
    public static func isFullscreen(_ space: UInt64) -> Bool {
        guard let main = mainConnection, let type = spaceType else { return false }
        return type(main(), space) == 4
    }

    /// The Spaces a window is on (more than one for "All Desktops" windows), or nil if unknown.
    public static func spaces(of windowID: CGWindowID) -> Set<UInt64>? {
        guard let main = mainConnection, let copy = spacesForWindows else { return nil }
        let ids = [NSNumber(value: windowID)] as CFArray
        // 0x7: current, other and user Spaces.
        guard let result = copy(main(), 0x7, ids)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return Set(result.map(\.uint64Value))
    }
}
