import AppKit
import StageOneCore
import WindowKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashSafety.install()
        Panels.shared.handlers[.saveScene] = { SaveSceneHotKey.showSaveBox() }
        Panels.shared.handlers[.scenes] = { ScenesPanel.show() }
        Panels.shared.handlers[.view] = { ViewPanel.show() }
        Panels.shared.handlers[.rewind] = { RewindPanel.show() }
        Panels.shared.handlers[.rules] = { RulesPanel.show() }
        CommandRouter.setPaused = { $0 ? Engine.pause() : Engine.resume() }
        MenuBarController.shared.install()
        // "· edited" is tracked by SceneEdited (SO-053), which compares the desk with the scene.

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

    /// Pause Stage One: puts every window back and hides the strip until resumed.
    static func pause() {
        Preferences.shared.paused = true
        StageController.shared.stop()
        StripManager.shared.stop()
    }

    /// Resume after a pause. Without Accessibility, reopens the walkthrough at that step.
    static func resume() {
        Preferences.shared.paused = false
        startIfReady()
        if !Permissions.accessibility {
            OnboardingWindow.shared.show(from: .accessibility)
            watchForAccessibility()
        }
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
