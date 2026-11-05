import AppKit
import StageOneCore
import WindowKit

/// Scenes on disk: ~/Library/Application Support/StageOne/Scenes/<slug>.stagescene
@MainActor
final class SceneStore: ObservableObject {
    static let shared = SceneStore()

    @Published private(set) var scenes: [StageScene] = []
    let directory: URL

    init(directory: URL = IPC.scenesDirectory) {
        self.directory = directory
        reload()
    }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        scenes = files.filter { $0.pathExtension == StageScene.fileExtension }
            .compactMap { try? StageScene.decode(Data(contentsOf: $0)) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func url(for scene: StageScene) -> URL {
        directory.appendingPathComponent(scene.slug).appendingPathExtension(StageScene.fileExtension)
    }

    func scene(named query: String) -> StageScene? {
        let q = query.lowercased()
        return scenes.first { $0.name.lowercased() == q || $0.slug == StageScene.slug(for: query) }
            ?? Fuzzy.rank(scenes, query: query, key: \.name).first
    }

    @discardableResult
    func write(_ scene: StageScene) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = url(for: scene)
        try scene.encoded().write(to: url, options: .atomic)
        reload()
        return url
    }

    func delete(_ scene: StageScene) {
        try? FileManager.default.removeItem(at: url(for: scene))
        if Preferences.shared.currentScene == scene.name { Preferences.shared.currentScene = nil }
        reload()
    }

    var current: StageScene? { Preferences.shared.currentScene.flatMap { n in scenes.first { $0.name == n } } }
}

/// Turns the live desk into a scene and back.
@MainActor
enum Scenes {
    /// The live desk as a scene (frames of parked windows are their return frames).
    static func capture(name: String) -> StageScene {
        let c = StageController.shared
        var windows = c.inventory.snapshots
        for (id, var snap) in windows {
            if let f = c.parking.savedFrame(id) { snap.frame = f; windows[id] = snap }
        }
        var scene = StageScene(name: name, desk: c.desk, windows: windows, layouts: ScreenLayouts.all())
        // Relaunch hints: how to bring each window back if its app is closed.
        for g in scene.groups.indices {
            for w in scene.groups[g].windows.indices {
                let win = scene.groups[g].windows[w]
                scene.groups[g].windows[w].relaunch = relaunchCommand(bundleID: win.bundleId, document: win.document)
            }
        }
        return scene
    }

    static func relaunchCommand(bundleID: String, document: String?) -> String {
        if let d = document, let url = URL(string: d), url.isFileURL {
            return "open -b \(bundleID) \"\(url.path)\""
        }
        return "open -b \(bundleID)"
    }

    /// SO-050: saves the desk under `name` and makes it the current scene.
    @discardableResult
    static func save(name: String, options: StageScene.Options = .init(), rule: StageScene.Rule? = nil) -> StageScene? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var scene = capture(name: trimmed)
        scene.options = options
        scene.rule = rule
        do {
            try SceneStore.shared.write(scene)
        } catch {
            Toast.shared.show("Couldn't save “\(trimmed)”", detail: error.localizedDescription)
            return nil
        }
        Preferences.shared.currentScene = trimmed
        Preferences.shared.sceneEdited = false
        let groups = scene.groups.filter { !$0.windows.isEmpty }.count
        Toast.shared.show("Saved “\(trimmed)”: \(groups) group\(groups == 1 ? "" : "s"), \(scene.windowCount) window\(scene.windowCount == 1 ? "" : "s")")
        return scene
    }

    /// A name for a new scene based on the active group and time of day.
    static func suggestedName() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Morning" : (hour < 17 ? "Afternoon" : "Evening")
        if let g = StageController.shared.desk.active?.name { return "\(g) · \(part)" }
        return "\(part) desk"
    }
}
