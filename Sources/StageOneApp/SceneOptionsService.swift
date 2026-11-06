import AppKit
import StageOneCore

/// SO-055: what a scene does besides placing windows: Do Not Disturb, Meeting mode,
/// hiding or quitting apps that aren't in it, and its wallpaper.
@MainActor
enum SceneOptionsService {
    /// Meeting mode arrives with SO-110; it registers here.
    static var setMeetingMode: ((Bool) -> Void)?

    /// Shortcuts the user can add so scenes can switch Do Not Disturb (macOS has no API for Focus).
    static let dndOnShortcut = "Stage One: Do Not Disturb On"
    static let dndOffShortcut = "Stage One: Do Not Disturb Off"

    static func apply(_ scene: StageScene) {
        let o = scene.options
        if o.dnd { setDoNotDisturb(true) }
        setMeetingMode?(o.meetingMode)
        if let path = o.wallpaper { setWallpaper(URL(fileURLWithPath: path)) }
        let others = otherApps(scene)
        if o.closeOthers, !others.isEmpty {
            // Give the restore toast a moment before asking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { askToQuit(others, scene: scene.name) } }
        } else if o.hideOthers {
            others.forEach { $0.hide() }
        }
    }

    private static func otherApps(_ scene: StageScene) -> [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != own && $0.bundleIdentifier != "com.apple.finder"
        }
        let others = Set(scene.appsNotInScene(running: running.compactMap(\.bundleIdentifier)))
        return running.filter { $0.bundleIdentifier.map(others.contains) ?? false }
    }

    private static func askToQuit(_ apps: [NSRunningApplication], scene: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Quit apps that aren't in “\(scene)”?"
        let names = apps.compactMap(\.localizedName).sorted()
        alert.informativeText = names.prefix(8).joined(separator: ", ") + (names.count > 8 ? " and \(names.count - 8) more" : "")
            + ". Apps with unsaved work will ask before closing."
        alert.icon = Mark.image(size: 64)
        alert.addButton(withTitle: "Quit \(apps.count) app\(apps.count == 1 ? "" : "s")")
        alert.addButton(withTitle: "Hide them")
        alert.addButton(withTitle: "Leave them")
        alert.window.appearance = NSAppearance(named: .aqua)
        switch alert.runModal() {
        case .alertFirstButtonReturn: apps.forEach { $0.terminate() }
        case .alertSecondButtonReturn: apps.forEach { $0.hide() }
        default: break
        }
    }

    private static func setWallpaper(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.shared.show("The scene's wallpaper is missing", detail: url.lastPathComponent)
            return
        }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    /// Runs the user's "Stage One: Do Not Disturb On/Off" shortcut, or explains how to add it.
    static func setDoNotDisturb(_ on: Bool) {
        let name = on ? dndOnShortcut : dndOffShortcut
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Process()
            list.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            list.arguments = ["list"]
            let pipe = Pipe()
            list.standardOutput = pipe
            let names: [String]
            do {
                try list.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                list.waitUntilExit()
                names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            } catch {
                names = []
            }
            guard names.contains(name) else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Toast.shared.show("Add a Shortcut to switch on Do Not Disturb",
                                          detail: "Name it “\(name)” with a Set Focus action. Stage One runs it for this scene.",
                                          action: (title: "Open Shortcuts", run: {
                                              if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                                                  NSWorkspace.shared.openApplication(at: url, configuration: .init())
                                              }
                                          }), duration: 8)
                    }
                }
                return
            }
            let run = Process()
            run.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            run.arguments = ["run", name]
            try? run.run()
        }
    }
}
