import AppKit
import ApplicationServices

/// Private but long-stable SPI used by every macOS window manager (Rectangle, AeroSpace,
/// yabai) to get the CGWindowID behind an AXUIElement.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, typed helpers over AXUIElement.
public enum AX {
    public static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    public static func attribute<T>(_ element: AXUIElement, _ name: String, as: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let v = value else { return nil }
        return v as? T
    }

    public static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name, as: String.self) }

    public static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        attribute(element, name, as: NSNumber.self)?.boolValue
    }

    public static func windows(of app: AXUIElement) -> [AXUIElement] {
        attribute(app, kAXWindowsAttribute, as: [AXUIElement].self) ?? []
    }

    public static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    public static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = point(element, kAXPositionAttribute), let s = size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    public static func setPosition(_ element: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    public static func setSize(_ element: AXUIElement, _ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v) == .success
    }

    @discardableResult
    public static func raise(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    public static func isStandardWindow(_ element: AXUIElement) -> Bool {
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        return role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    /// The CGWindowID of the frontmost app's focused window.
    @MainActor
    public static func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &value) == .success, let v = value,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return windowID(of: v as! AXUIElement)
    }

    public static func isMinimized(_ element: AXUIElement) -> Bool { bool(element, kAXMinimizedAttribute) ?? false }
    public static func isFullscreen(_ element: AXUIElement) -> Bool { bool(element, "AXFullScreen") ?? false }
}
