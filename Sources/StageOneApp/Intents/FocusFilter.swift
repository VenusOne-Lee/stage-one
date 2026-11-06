import AppIntents
import StageOneCore

/// SO-072: in System Settings › Focus › (a Focus) › Focus filters › Stage One, a Focus picks
/// a scene. When that Focus turns on, the scene is restored after the usual 5-second
/// countdown with Skip, and the run shows in the rule log.
struct StageOneFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Restore a scene"
    static let description: IntentDescription? = IntentDescription("Stage One puts this scene on stage when the Focus turns on.")

    @Parameter(title: "Scene")
    var scene: SceneEntity?

    var displayRepresentation: DisplayRepresentation {
        if let scene { return DisplayRepresentation(title: "Restore \(scene.id)") }
        return DisplayRepresentation(title: "No scene")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The system also calls this when the Focus ends, with the filter's values cleared:
        // nothing is restored then, so the desk stays as it is.
        guard let chosen = scene else { return .result() }
        let store = SceneStore.shared
        store.reload()
        if let s = store.scenes.first(where: { $0.name == chosen.id }) {
            RuleService.shared.run(s, reason: "Focus turned on", trigger: .focus)
        }
        return .result()
    }
}
