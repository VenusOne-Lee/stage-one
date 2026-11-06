import AppIntents
import StageOneCore

/// A saved scene, for Focus filters (SO-072), Shortcuts and Spotlight (SO-090).
struct SceneEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scene")
    static let defaultQuery = SceneQuery()

    /// Scenes are identified by name; names are unique on disk (one file per slug).
    let id: String
    let windowCount: Int

    init(_ scene: StageScene) {
        id = scene.name
        windowCount = SceneCatalog.windowCount(scene)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)", subtitle: "\(windowCount) windows")
    }
}

struct SceneQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SceneEntity] {
        SceneCatalog.scenes(named: identifiers, in: SceneCatalog.load()).map(SceneEntity.init)
    }

    func entities(matching string: String) async throws -> [SceneEntity] {
        SceneCatalog.search(string, in: SceneCatalog.load()).map(SceneEntity.init)
    }

    func suggestedEntities() async throws -> [SceneEntity] {
        SceneCatalog.load().map(SceneEntity.init)
    }
}
