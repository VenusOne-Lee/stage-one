import AppIntents
import StageOneCore

/// SO-090: Stage One's actions for Shortcuts, Spotlight and Siri. Each runs in the app and
/// does what the matching menu, command bar row or `stage` command does.

struct StageOneIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }

    @MainActor static func requireRunning() throws {
        guard StageController.shared.isRunning else {
            throw StageOneIntentError(message: "Stage One is paused or still needs Accessibility access.")
        }
    }
}

struct RestoreSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Restore Scene"
    static let description: IntentDescription? = IntentDescription("Puts a saved scene's windows back where they were. Undo is offered for 30 seconds.")

    @Parameter(title: "Scene")
    var scene: SceneEntity

    static var parameterSummary: some ParameterSummary { Summary("Restore \(\.$scene)") }

    init() {}
    init(scene: SceneEntity) { self.scene = scene }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try StageOneIntentError.requireRunning()
        let store = SceneStore.shared
        store.reload()
        guard let s = store.scenes.first(where: { $0.name == scene.id }) else {
            throw StageOneIntentError(message: "There's no scene called “\(scene.id)” any more.")
        }
        let outcome = SceneRestore.restore(s)
        let missing = outcome.missing.isEmpty ? "" : " \(outcome.missing.count) still opening."
        return .result(dialog: "Restored \(s.name).\(missing)")
    }
}

struct SaveSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Scene"
    static let description: IntentDescription? = IntentDescription("Saves every group and window on the desk as a scene.")

    @Parameter(title: "Name", requestValueDialog: "What should the scene be called?")
    var name: String

    static var parameterSummary: some ParameterSummary { Summary("Save the desk as \(\.$name)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<SceneEntity> {
        try StageOneIntentError.requireRunning()
        guard let s = Scenes.save(name: name) else {
            throw StageOneIntentError(message: "Couldn't save the scene.")
        }
        return .result(value: SceneEntity(s), dialog: "Saved \(s.name).")
    }
}

struct RewindToIntent: AppIntent {
    static let title: LocalizedStringResource = "Rewind Desk"
    static let description: IntentDescription? = IntentDescription("Puts the desk back the way it was at a time in the last 7 days.")

    @Parameter(title: "Time")
    var time: Date

    static var parameterSummary: some ParameterSummary { Summary("Rewind the desk to \(\.$time)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try StageOneIntentError.requireRunning()
        let reply = RewindStore.shared.rewind(to: time)
        guard reply.ok else { throw StageOneIntentError(message: reply.message) }
        return .result(dialog: "\(reply.message)")
    }
}

struct ShowGroupIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Group"
    static let description: IntentDescription? = IntentDescription("Brings a group onto the stage.")

    @Parameter(title: "Group")
    var group: GroupEntity

    static var parameterSummary: some ParameterSummary { Summary("Show \(\.$group)") }

    init() {}
    init(group: GroupEntity) { self.group = group }

    @MainActor
    func perform() async throws -> some IntentResult {
        try StageOneIntentError.requireRunning()
        let c = StageController.shared
        guard c.desk.groups.contains(where: { $0.id == group.id }) else {
            throw StageOneIntentError(message: "That group isn't on the desk any more.")
        }
        c.switchTo(group.id)
        return .result()
    }
}

struct ArrangeIntent: AppIntent {
    static let title: LocalizedStringResource = "Arrange Stage"
    static let description: IntentDescription? = IntentDescription("Arranges the windows on stage in a layout.")

    @Parameter(title: "Layout", default: .halves)
    var layout: ArrangeLayout

    static var parameterSummary: some ParameterSummary { Summary("Arrange the stage in \(\.$layout)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        try StageOneIntentError.requireRunning()
        LayoutService.apply(layout.kind)
        return .result()
    }
}

struct ToggleMeetingModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Meeting Mode"
    static let description: IntentDescription? = IntentDescription("Turns Meeting mode on or off.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let set = SceneOptionsService.setMeetingMode else {
            throw StageOneIntentError(message: "Meeting mode isn't in this version of Stage One yet.")
        }
        let on = !SceneOptionsService.meetingModeOn
        set(on)
        let dialog: IntentDialog = on ? "Meeting mode is on." : "Meeting mode is off."
        return .result(dialog: dialog)
    }
}

/// Phrases for Siri and Spotlight. Each phrase names the app, as App Shortcuts require.
struct StageOneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RestoreSceneIntent(), phrases: [
            "Restore \(\.$scene) in \(.applicationName)",
            "Restore a scene in \(.applicationName)",
            "\(.applicationName) restore \(\.$scene)",
        ], shortTitle: "Restore Scene", systemImageName: "rectangle.stack")
        AppShortcut(intent: SaveSceneIntent(), phrases: [
            "Save a scene in \(.applicationName)",
            "Save my desk in \(.applicationName)",
        ], shortTitle: "Save Scene", systemImageName: "square.and.arrow.down")
        AppShortcut(intent: ShowGroupIntent(), phrases: [
            "Show \(\.$group) in \(.applicationName)",
            "Switch group in \(.applicationName)",
        ], shortTitle: "Show Group", systemImageName: "square.on.square")
        AppShortcut(intent: ArrangeIntent(), phrases: [
            "Arrange the stage in \(.applicationName)",
            "Arrange windows in \(.applicationName)",
        ], shortTitle: "Arrange", systemImageName: "rectangle.split.2x1")
        AppShortcut(intent: RewindToIntent(), phrases: [
            "Rewind my desk in \(.applicationName)",
        ], shortTitle: "Rewind", systemImageName: "clock.arrow.circlepath")
        AppShortcut(intent: ToggleMeetingModeIntent(), phrases: [
            "Toggle meeting mode in \(.applicationName)",
        ], shortTitle: "Meeting Mode", systemImageName: "person.2.wave.2")
    }
}
