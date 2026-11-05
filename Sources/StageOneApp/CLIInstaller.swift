import AppKit

/// SO-100: links the bundled `stage` tool into /usr/local/bin. Asks for an admin
/// password once, through the standard macOS prompt.
@MainActor
enum CLIInstaller {
    static let target = "/usr/local/bin/stage"

    static var bundled: String? {
        let p = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/stage").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    /// True when /usr/local/bin/stage points at this app's copy.
    static var isInstalled: Bool {
        guard let b = bundled, let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: target) else { return false }
        return dest == b
    }

    @discardableResult
    static func install() -> Bool {
        guard let src = bundled else {
            Toast.shared.show("The stage tool isn't in this build", detail: "Run Stage One from its .app bundle.")
            return false
        }
        let q: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "mkdir -p /usr/local/bin && ln -sf \(q(src)) \(q(target))"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            Toast.shared.show("Couldn't install the stage tool", detail: error[NSAppleScript.errorMessage] as? String)
            return false
        }
        guard isInstalled else { return false }
        Toast.shared.show("Installed `stage`", detail: "Try: stage list")
        return true
    }
}
