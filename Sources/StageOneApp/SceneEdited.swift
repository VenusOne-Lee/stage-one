import AppKit
import StageOneCore
import WindowKit

/// SO-053: when the desk differs from the current scene, the menu bar and the scene card
/// show "· edited", and the card offers "Update".
@MainActor
enum SceneEdited {
    private static var installed = false
    private static var pending: DispatchWorkItem?

    static func install() {
        guard !installed else { return }
        installed = true
        StageController.shared.onDeskChange.append { SceneEdited.schedule() }
        StageController.shared.onWindowEvent.append { e in
            switch e {
            case .moved, .resized, .created, .destroyed: SceneEdited.schedule()
            default: break
            }
        }
        schedule()
    }

    static func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { SceneEdited.check() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    static func check() {
        let c = StageController.shared
        guard !c.isSwitching else { schedule(); return }
        guard let current = SceneStore.shared.current else {
            if Preferences.shared.sceneEdited { Preferences.shared.sceneEdited = false }
            return
        }
        let edited = Scenes.capture(name: current.name).fingerprint() != current.fingerprint()
        if Preferences.shared.sceneEdited != edited { Preferences.shared.sceneEdited = edited }
    }

    /// "Update": overwrite the current scene with the desk as it is now, keeping its rule and options.
    static func updateCurrent() {
        guard let current = SceneStore.shared.current else { return }
        Scenes.save(name: current.name, options: current.options, rule: current.rule)
    }
}
