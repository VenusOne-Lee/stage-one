import AppKit
import Foundation

/// SO-002: reads and changes Apple's Stage Manager setting. Stage Manager and Stage One
/// both hide and move windows, so they fight if both are on.
/// Uses /usr/bin/defaults because UserDefaults(suiteName:) cannot reliably see another app's domain.
enum AppleStageManager {
    private static let domain = "com.apple.WindowManager"
    private static let key = "GloballyEnabled"

    /// True when Stage Manager is on. A missing key means it was never turned on.
    static var isOn: Bool {
        guard let out = defaults(["read", domain, key]) else { return false }
        let v = out.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    /// Turns Stage Manager on or off. Returns true when the write succeeded.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        defaults(["write", domain, key, "-bool", on ? "true" : "false"]) != nil
    }

    /// Opens System Settings › Desktop & Dock, where Stage Manager lives.
    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs `defaults` and returns stdout, or nil when it exits non-zero.
    private static func defaults(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
