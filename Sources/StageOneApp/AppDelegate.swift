import AppKit
import StageOneCore
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Mark.image(size: 18)
        item.button?.toolTip = "Stage One"
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Stage One", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
