import AppKit
import StageOneCore
import WindowKit

/// SO-015: flags apps that ignore Accessibility moves and lets their windows float above
/// the stage. Users can add or change exceptions in Settings › Rules.
@MainActor
enum AppExceptionsService {
    private static var installed = false

    static func install() {
        let c = StageController.shared
        c.parking.onIgnoredMove = { window in detected(window) }
        guard !installed else { return }
        installed = true
        c.onWindowEvent.append { e in
            if case .appLaunched(let pid) = e, let app = NSRunningApplication(processIdentifier: pid) { check(app) }
        }
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.forEach(check)
    }

    /// Flags a known or game app the first time it's seen.
    static func check(_ app: NSRunningApplication) {
        guard let bundle = app.bundleIdentifier else { return }
        let name = app.localizedName ?? bundle
        var list = Preferences.shared.appExceptions
        var added = false
        if Uncooperative.known[bundle] != nil {
            added = Uncooperative.flag(&list, bundleID: bundle, name: name, reason: .knownList)
        } else if Uncooperative.isGame(category: category(of: app)) {
            added = Uncooperative.flag(&list, bundleID: bundle, name: name, reason: .game)
        }
        if added { update(list) }
    }

    /// Parking failed: the app moved its window back.
    private static func detected(_ window: TrackedWindow) {
        var list = Preferences.shared.appExceptions
        let name = window.snapshot.appName
        guard Uncooperative.flag(&list, bundleID: window.bundleID, name: name, reason: .detected) else { return }
        update(list)
        Toast.shared.show("\(name) floats above the stage",
                          detail: "It won't let Stage One move its windows. Change this in Settings › Rules.",
                          action: (title: "Settings", run: { SettingsWindow.shared.show(tab: .rules) }))
    }

    /// Saves the list and applies it: newly floating apps get their windows back on screen.
    static func update(_ list: [AppException]) {
        Preferences.shared.appExceptions = list
        apply()
    }

    static func apply() {
        let c = StageController.shared
        let floating = Uncooperative.floating(Preferences.shared.appExceptions)
        guard floating != c.inventory.floatingBundleIDs else { return }
        for w in c.inventory.windows where floating.contains(w.bundleID) && c.parking.isParked(w.id) {
            c.parking.unpark(w)
        }
        c.inventory.floatingBundleIDs = floating
        c.inventory.rescan()
        c.enforceStage()
    }

    private static func category(of app: NSRunningApplication) -> String? {
        guard let url = app.bundleURL else { return nil }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }
}
