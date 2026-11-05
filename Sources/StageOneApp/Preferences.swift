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
    /// Persisted desk (groups), so groups survive a relaunch.
    var savedDesk: Data? {
        get { d.data(forKey: "desk") }
        set { d.set(newValue, forKey: "desk") }
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
    }
}
