import AppKit
import StageOneCore

/// SO-135: Help › Send feedback. Opens a pre-filled GitHub issue with the Stage One and
/// macOS versions, and the names of open apps only if the person ticks the box. Stage One
/// has no analytics; nothing leaves the Mac unless the issue is submitted.
@MainActor
enum FeedbackService {
    static func send() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Send feedback"
        alert.informativeText = "This opens a new GitHub issue in your browser with your Stage One and macOS versions filled in. Nothing is sent until you submit it. Stage One collects no analytics."
        alert.icon = Mark.image(size: 64)
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Cancel")
        let include = NSButton(checkboxWithTitle: "Include the names of open apps (helps with app-specific bugs)", target: nil, action: nil)
        include.state = .off
        alert.accessoryView = include
        alert.window.appearance = NSAppearance(named: .aqua)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let apps: [String]? = include.state == .on ? openApps() : nil
        NSWorkspace.shared.open(Feedback.issueURL(appVersion: appVersion, macOS: macOSVersion, apps: apps))
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = info?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Regular apps the person can see, not background helpers.
    static func openApps() -> [String] {
        Array(Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)))
    }
}
