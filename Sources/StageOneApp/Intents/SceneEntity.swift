import AppIntents
import StageOneCore

/// A saved scene, for Focus filters (SO-072), Shortcuts and Spotlight (SO-090).
struct SceneEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scene")
    static let defaultQuery = SceneQuery()

    /// Scenes are identified by name; names are unique on disk (one file per slug).
    let id: String
    /// SO-122: properties later actions in a shortcut can read.
    @Property(title: "Name") var name: String
    @Property(title: "Windows") var windowCount: Int
    @Property(title: "Saved") var savedAt: Date
    @Property(title: "Has a rule") var hasRule: Bool

    init(_ scene: StageScene) {
        id = scene.name
        name = scene.name
        windowCount = SceneCatalog.windowCount(scene)
        savedAt = scene.savedAt
        hasRule = scene.rule?.enabled ?? false
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
