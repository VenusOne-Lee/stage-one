import AppKit
import StageOneCore
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashSafety.install()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Mark.image(size: 18)
        item.button?.toolTip = "Stage One"
        let menu = NSMenu()
        let welcome = NSMenuItem(title: "Welcome to Stage One…", action: #selector(showOnboarding(_:)), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Stage One", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        // The engine only runs once Accessibility is trusted. Until then the walkthrough explains why.
        Engine.startIfReady()
        if !Preferences.shared.onboardingDone {
            OnboardingWindow.shared.show()
        } else if !Permissions.accessibility {
            OnboardingWindow.shared.show(from: .accessibility)
        }
        if !Permissions.accessibility { Engine.watchForAccessibility() }
        UpdateChecker.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        StageController.shared.stop()
    }

    @objc private func showOnboarding(_ sender: Any?) {
        OnboardingWindow.shared.show()
    }
}

/// Starts the window engine and the strip once Accessibility is trusted.
@MainActor
enum Engine {
    private static var watcher: Timer?

    /// Starts the controller and the strip if Accessibility is trusted and Stage One is not paused.
    static func startIfReady() {
        guard Permissions.accessibility, !Preferences.shared.paused else { return }
        if !StageController.shared.isRunning { StageController.shared.start() }
        StripManager.shared.start()
    }

    /// Polls once a second until Accessibility is granted, then starts the engine. No relaunch needed.
    static func watchForAccessibility() {
        guard watcher == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Engine.tick() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        watcher = t
    }

    private static func tick() {
        guard Permissions.accessibility else { return }
        watcher?.invalidate()
        watcher = nil
        startIfReady()
    }
}
