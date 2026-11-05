import AppKit
import StageOneCore

/// SO-101: `stageone://` links. Destructive commands ask first.
@MainActor
extension CommandRouter {
    // MARK: stageone:// URLs (SO-101)

    static func open(_ url: URL) {
        guard let command = Command(url: url) else {
            Toast.shared.show("Stage One didn't understand that link", detail: url.absoluteString)
            return
        }
        if command.isDestructive {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Run this from a link?"
            alert.informativeText = "A link asked Stage One to \(describe(command)). Your windows will move."
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let reply = run(command)
        if !reply.ok || !command.showsOwnToast { Toast.shared.show(reply.message, duration: 3) }
    }

    private static func describe(_ c: Command) -> String {
        switch c {
        case .restore(let s): return "restore the scene “\(s)”"
        case .export(let s, let p, _): return "write the scene “\(s)” to \(p)"
        case .rewind: return "rewind the desk"
        case .importScene(let p): return "import \((p as NSString).lastPathComponent)"
        default: return "change your desk"
        }
    }
}


private extension Command {
    /// Commands whose app-side code already shows a toast.
    var showsOwnToast: Bool {
        switch self {
        case .save, .restore: return true
        default: return false
        }
    }
}

/// Registers for kAEGetURL so `open stageone://…` works without touching the app delegate.
@MainActor
final class URLHandler: NSObject {
    static let shared = URLHandler()

    func install() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handle(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        CommandRouter.open(url)
    }
}
