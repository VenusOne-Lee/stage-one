import Foundation
import StageOneCore

/// User settings, stored in UserDefaults. One shared instance; views observe it.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var stripEdge: ScreenEdge { didSet { d.set(stripEdge.rawValue, forKey: "stripEdge") } }
    @Published var overlapMode: OverlapMode { didSet { d.set(overlapMode.rawValue, forKey: "overlapMode") } }
    @Published var stripSize: StripSize { didSet { d.set(stripSize.rawValue, forKey: "stripSize") } }
    /// Show thumbnails (needs Screen Recording) or app icon tiles.
    @Published var livePreviews: Bool { didSet { d.set(livePreviews, forKey: "livePreviews") } }
    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    /// Name of the scene currently on stage, if any.
    @Published var currentScene: String? { didSet { d.set(currentScene, forKey: "currentScene") } }
    /// Hotkey modifier for group switching (⌥ by default).
    @Published var groupHotkeysEnabled: Bool { didSet { d.set(groupHotkeysEnabled, forKey: "groupHotkeysEnabled") } }
    /// SO-002: Stage One turned Apple's Stage Manager off, so Settings can offer to turn it back on.
    @Published var stageManagerTurnedOff: Bool { didSet { d.set(stageManagerTurnedOff, forKey: "stageManagerTurnedOff") } }
    /// SO-014: one set of groups for every Space, or one per Space.
    @Published var spacesMode: SpacesMode { didSet { d.set(spacesMode.rawValue, forKey: "spacesMode") } }
    /// SO-042: layout shortcuts the user changed, by `LayoutShortcut` raw value.
    @Published var layoutShortcuts: [String: Shortcut] {
        didSet { d.set(try? JSONEncoder().encode(layoutShortcuts), forKey: "layoutShortcuts") }
    }
    /// SO-015: apps Stage One leaves alone (their windows float above the stage).
    @Published var appExceptions: [AppException] {
        didSet { d.set(try? JSONEncoder().encode(appExceptions), forKey: "appExceptions") }
    }
    /// SO-110 / SO-111: what Meeting mode hides.
    @Published var privateList: PrivateList {
        didSet { d.set(try? JSONEncoder().encode(privateList), forKey: "privateList") }
    }
    /// SO-110: turn Meeting mode on while the screen is shared.
    @Published var meetingAuto: Bool { didSet { d.set(meetingAuto, forKey: "meetingAuto") } }
    /// SO-121: MCP tools allowed to change the desk without asking.
    @Published var mcpAllowed: [String] { didSet { d.set(mcpAllowed, forKey: "mcpAllowed") } }
    /// The desk differs from the current scene (shown as "· edited"). Not persisted.
    @Published var sceneEdited = false
    /// Persisted desk (groups), so groups survive a relaunch.
    var savedDesk: Data? {
        get { d.data(forKey: "desk") }
        set { d.set(newValue, forKey: "desk") }
    }

    /// SO-014: the desks of Spaces that aren't showing, and which Space the desk belongs to.
    var savedSpaceDesks: Data? {
        get { d.data(forKey: "spaceDesks") }
        set { d.set(newValue, forKey: "spaceDesks") }
    }
    var savedSpaceKey: String? {
        get { d.string(forKey: "spaceKey") }
        set { d.set(newValue, forKey: "spaceKey") }
    }

    private init() {
        stripEdge = ScreenEdge(rawValue: d.string(forKey: "stripEdge") ?? "") ?? .left
        overlapMode = OverlapMode(rawValue: d.string(forKey: "overlapMode") ?? "") ?? .reserve
        stripSize = StripSize(rawValue: d.string(forKey: "stripSize") ?? "") ?? .full
        livePreviews = d.object(forKey: "livePreviews") as? Bool ?? true
        paused = d.bool(forKey: "paused")
        onboardingDone = d.bool(forKey: "onboardingDone")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        currentScene = d.string(forKey: "currentScene")
        groupHotkeysEnabled = d.object(forKey: "groupHotkeysEnabled") as? Bool ?? true
        stageManagerTurnedOff = d.bool(forKey: "stageManagerTurnedOff")
        layoutShortcuts = d.data(forKey: "layoutShortcuts").flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) } ?? [:]
        appExceptions = d.data(forKey: "appExceptions").flatMap { try? JSONDecoder().decode([AppException].self, from: $0) } ?? []
        privateList = d.data(forKey: "privateList").flatMap { try? JSONDecoder().decode(PrivateList.self, from: $0) } ?? PrivateList()
        meetingAuto = d.object(forKey: "meetingAuto") as? Bool ?? true
        mcpAllowed = d.stringArray(forKey: "mcpAllowed") ?? []
        spacesMode = SpacesMode(rawValue: d.string(forKey: "spacesMode") ?? "") ?? .shared
    }
}
