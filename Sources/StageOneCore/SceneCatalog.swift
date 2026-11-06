import Foundation

/// SO-072/SO-090: the saved scenes as App Intents see them. Pure and off the main actor, so
/// entity queries can run wherever the system calls them.
public enum SceneCatalog {
    /// Every scene in `directory`, newest first.
    public static func load(from directory: URL = IPC.scenesDirectory) -> [StageScene] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == StageScene.fileExtension }
            .compactMap { try? StageScene.decode(Data(contentsOf: $0)) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// Scenes whose names are in `names`, in that order.
    public static func scenes(named names: [String], in scenes: [StageScene]) -> [StageScene] {
        names.compactMap { n in scenes.first { $0.name == n } }
    }

    /// Scenes matching a typed query (fuzzy); all of them for an empty query.
    public static func search(_ query: String, in scenes: [StageScene]) -> [StageScene] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? scenes : Fuzzy.rank(scenes, query: q, key: \.name)
    }

    /// Number of windows a scene puts back.
    public static func windowCount(_ scene: StageScene) -> Int {
        scene.groups.reduce(0) { $0 + $1.windows.count }
    }
}
