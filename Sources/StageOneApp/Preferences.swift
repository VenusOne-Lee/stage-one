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
        spacesMode = SpacesMode(rawValue: d.string(forKey: "spacesMode") ?? "") ?? .shared
    }
}
