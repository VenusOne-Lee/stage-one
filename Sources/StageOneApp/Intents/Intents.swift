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
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<SceneEntity> {
        try StageOneIntentError.requireRunning()
        let store = SceneStore.shared
        store.reload()
        guard let s = store.scenes.first(where: { $0.name == scene.id }) else {
            throw StageOneIntentError(message: "There's no scene called “\(scene.id)” any more.")
        }
        let outcome = SceneRestore.restore(s)
        let missing = outcome.missing.isEmpty ? "" : " \(outcome.missing.count) still opening."
        return .result(value: SceneEntity(s), dialog: "Restored \(s.name).\(missing)")
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

    /// Returns the time of the snapshot it went back to.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Date> {
        try StageOneIntentError.requireRunning()
        let store = RewindStore.shared
        store.reload()
        let dates = store.snapshots.map(\.date)
        let reply = store.rewind(to: time)
        guard reply.ok, let i = RewindPolicy.target(for: time, in: dates, now: Date()) else {
            throw StageOneIntentError(message: reply.message)
        }
        return .result(value: dates[i], dialog: "\(reply.message)")
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
    func perform() async throws -> some IntentResult & ReturnsValue<GroupEntity> {
        try StageOneIntentError.requireRunning()
        let c = StageController.shared
        guard let g = c.desk.groups.first(where: { $0.id == group.id }) else {
            throw StageOneIntentError(message: "That group isn't on the desk any more.")
        }
        c.switchTo(g.id)
        return .result(value: GroupEntity(g, onStage: true))
    }
}

struct ArrangeIntent: AppIntent {
    static let title: LocalizedStringResource = "Arrange Stage"
    static let description: IntentDescription? = IntentDescription("Arranges the windows on stage in a layout.")

    @Parameter(title: "Layout", default: .halves)
    var layout: ArrangeLayout

    static var parameterSummary: some ParameterSummary { Summary("Arrange the stage in \(\.$layout)") }

    /// Returns the group on stage, which it arranged.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GroupEntity> {
        try StageOneIntentError.requireRunning()
        guard let g = StageController.shared.desk.active else {
            throw StageOneIntentError(message: "There's no group on stage to arrange.")
        }
        LayoutService.apply(layout.kind)
        return .result(value: GroupEntity(g, onStage: true))
    }
}

/// SO-110 / SO-122: on, off or toggle. Returns whether Meeting mode ends up on.
struct ToggleMeetingModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Meeting Mode"
    static let description: IntentDescription? = IntentDescription("Turns Meeting mode on, off, or the other way. While it's on, private apps are covered while you share your screen.")

    @Parameter(title: "Mode", default: .toggle)
    var mode: MeetingSwitch

    static var parameterSummary: some ParameterSummary { Summary("\(\.$mode) Meeting mode") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let m = MeetingMode.shared
        switch mode {
        case .on: m.set(true)
        case .off: m.set(false)
        case .toggle: m.toggle()
        }
        let dialog: IntentDialog = m.on ? "Meeting mode is on." : "Meeting mode is off."
        return .result(value: m.on, dialog: dialog)
    }
}

enum MeetingSwitch: String, AppEnum {
    case on, off, toggle

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meeting mode")
    static let caseDisplayRepresentations: [MeetingSwitch: DisplayRepresentation] = [
        .on: "Turn on",
        .off: "Turn off",
        .toggle: "Toggle",
    ]
}

/// SO-122: actions that only read, so shortcuts can loop over scenes and groups.
struct GetScenesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Scenes"
    static let description: IntentDescription? = IntentDescription("Gets your saved scenes, newest first.")

    static var parameterSummary: some ParameterSummary { Summary("Get all scenes") }

    func perform() async throws -> some IntentResult & ReturnsValue<[SceneEntity]> {
        .result(value: SceneCatalog.load().map(SceneEntity.init))
    }
}

struct GetCurrentSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Scene"
    static let description: IntentDescription? = IntentDescription("Gets the scene that's on stage, if there is one.")

    static var parameterSummary: some ParameterSummary { Summary("Get the current scene") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SceneEntity> {
        let store = SceneStore.shared
        store.reload()
        guard let s = store.current else { throw StageOneIntentError(message: "No scene is on stage right now.") }
        return .result(value: SceneEntity(s))
    }
}

struct GetGroupsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Groups"
    static let description: IntentDescription? = IntentDescription("Gets the window groups on the desk, in strip order.")

    static var parameterSummary: some ParameterSummary { Summary("Get the groups on the desk") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GroupEntity]> {
        let d = StageController.shared.desk
        return .result(value: d.groups.map { GroupEntity($0, onStage: $0.id == d.activeID) })
    }
}

struct GetRewindPointsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Rewind Points"
    static let description: IntentDescription? = IntentDescription("Gets the times the desk can be rewound to, oldest first. Snapshots are kept for 7 days.")

    static var parameterSummary: some ParameterSummary { Summary("Get rewind points") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[Date]> {
        let store = RewindStore.shared
        store.reload()
        return .result(value: store.snapshots.map(\.date))
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
            "\(\.$mode) meeting mode in \(.applicationName)",
        ], shortTitle: "Meeting Mode", systemImageName: "person.2.wave.2")
    }
}
