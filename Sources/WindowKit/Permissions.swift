import AppKit
import ApplicationServices
import CoreGraphics

/// Accessibility and Screen Recording access (used by onboarding, SO-001).
@MainActor
public enum Permissions {
    public static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Stage One to the Accessibility list.
    public static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    public static func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
