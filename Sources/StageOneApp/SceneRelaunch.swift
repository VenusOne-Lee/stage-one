import AppKit
import StageOneCore
import WindowKit

/// SO-052: windows a scene wants that aren't open are brought back by opening their
/// document with its app, or by launching the app. Restore waits up to 10 seconds per
/// app, then places the new windows. A progress chip reads "Opening 3 apps…".
@MainActor
enum SceneRelaunch {
    static func install() {
        SceneRestore.relaunchMissing = { scene, missing in SceneRelaunch.relaunch(scene, missing) }
    }

    static func relaunch(_ scene: StageScene, _ missing: [(group: Int, window: StageScene.Window)]) {
        let byApp = Dictionary(grouping: missing, by: { $0.window.bundleId })
        let apps = byApp.keys.sorted()
        guard !apps.isEmpty else { return }
        Toast.shared.show("Opening \(apps.count) app\(apps.count == 1 ? "" : "s")…", detail: apps.compactMap(appName).joined(separator: ", "),
                          duration: 0, progress: true)
        let ws = NSWorkspace.shared
        for bundle in apps {
            guard let appURL = ws.urlForApplication(withBundleIdentifier: bundle) else { continue }
            let docs = (byApp[bundle] ?? []).compactMap { $0.window.document }.compactMap(URL.init(string:)).filter(\.isFileURL)
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            if docs.isEmpty {
                ws.openApplication(at: appURL, configuration: config, completionHandler: nil)
            } else {
                ws.open(docs, withApplicationAt: appURL, configuration: config, completionHandler: nil)
            }
        }
        waitAndPlace(scene: scene, bundles: Set(apps), deadline: Date().addingTimeInterval(10), missing: missing)
    }

    /// Polls the inventory until the apps have windows (or 10s pass), then matches and places them.
    private static func waitAndPlace(scene: StageScene, bundles: Set<String>, deadline: Date,
                                     missing: [(group: Int, window: StageScene.Window)]) {
        let c = StageController.shared
        c.inventory.rescan()
        let need = Dictionary(grouping: missing, by: { $0.window.bundleId }).mapValues(\.count)
        let have = Dictionary(grouping: c.inventory.windows.filter { bundles.contains($0.bundleID) }, by: \.bundleID).mapValues(\.count)
        let ready = need.allSatisfy { have[$0.key, default: 0] >= $0.value }
        if ready || Date() >= deadline {
            place(scene: scene, missing: missing)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { waitAndPlace(scene: scene, bundles: bundles, deadline: deadline, missing: missing) }
        }
    }

    private static func place(scene: StageScene, missing: [(group: Int, window: StageScene.Window)]) {
        let c = StageController.shared
        let claimed = Set(c.desk.groups.filter { $0.name != "Other" }.flatMap(\.windowIDs))
        let candidates = c.inventory.windows.filter { !claimed.contains($0.id) }.map(\.snapshot)
        let result = IdentityMatcher.match(saved: missing.map(\.window), live: candidates, threshold: 0.5)
        var placed = 0
        for m in result.matches {
            let (gi, saved) = missing[m.savedIndex]
            guard scene.groups.indices.contains(gi),
                  let target = c.desk.groups.first(where: { $0.name == scene.groups[gi].name }),
                  let w = c.inventory[m.windowID] else { continue }
            let frame = SceneRestore.reflowed(saved.cgFrame, scene: scene, display: scene.groups[gi].display)
            c.move(window: w.id, to: target.id)
            if c.parking.isParked(w.id) { c.parking.setSavedFrame(w.id, frame) } else { c.mover.setFrame(w, frame) }
            placed += 1
        }
        let left = missing.count - placed
        Toast.shared.show(left == 0 ? "“\(scene.name)” is ready" : "“\(scene.name)” is ready, \(left) window\(left == 1 ? "" : "s") couldn't be found",
                          duration: 3)
        Preferences.shared.sceneEdited = false
    }

    private static func appName(_ bundle: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { $0.deletingPathExtension().lastPathComponent }
    }
}
