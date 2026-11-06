import AppKit
import StageOneCore
import WindowKit

/// SO-051: restore a scene. Existing windows are matched by identity and moved into their
/// groups and frames; windows that aren't in the scene go to an "Other" group (parked).
/// Nothing is closed. Undoable for 30 seconds.
@MainActor
enum SceneRestore {
    struct Outcome {
        var placed: Int
        var missing: [(group: Int, window: StageScene.Window)]
    }

    /// Hook for SO-052: relaunch apps for windows that weren't found.
    static var relaunchMissing: ((StageScene, [(group: Int, window: StageScene.Window)]) -> Void)?

    private static var undoScene: StageScene?
    private static var undoExpiry: Date?

    /// When the last restore started; new-window placement (SO-043) holds off for a while
    /// after it, because relaunched apps' windows are being placed by the scene.
    private(set) static var lastRestoreAt: Date?

    @discardableResult
    static func restore(_ scene: StageScene, undoable: Bool = true, relaunch: Bool = true, quiet: Bool = false) -> Outcome {
        lastRestoreAt = Date()
        let c = StageController.shared
        if undoable {
            undoScene = Scenes.capture(name: "Before restoring \(scene.name)")
            undoExpiry = Date().addingTimeInterval(30)
        }
        let outcome = apply(scene)
        if !quiet {
            var notes: [String] = []
            if !outcome.missing.isEmpty { notes.append("\(outcome.missing.count) window\(outcome.missing.count == 1 ? "" : "s") not open yet") }
            // SO-056: say what happened to windows from displays that aren't connected.
            if folded > 0 {
                let gone = DisplayFold.missing(scene.displays, connected: Set(NSScreen.screens.map(Displays.stableID(of:)))).count
                notes.append("Saved on \(scene.displays.count) displays, \(gone) not connected: \(folded) window\(folded == 1 ? "" : "s") moved here at the same size")
            }
            let detail = notes.isEmpty ? nil : notes.joined(separator: ". ")
            let undo: (title: String, run: () -> Void)? = undoable ? (title: "Undo", run: { SceneRestore.undo() }) : nil
            Toast.shared.show("Restored “\(scene.name)”", detail: detail, action: undo, duration: undoable ? 30 : 4)
        }
        if !scene.name.hasPrefix("Before restoring") {
            Preferences.shared.currentScene = scene.name
            Preferences.shared.sceneEdited = false
        }
        if relaunch, !outcome.missing.isEmpty { relaunchMissing?(scene, outcome.missing) }
        if !quiet { SceneOptionsService.apply(scene) }
        c.captureAll()
        return outcome
    }

    static func undo() {
        guard let s = undoScene, let exp = undoExpiry, exp > Date() else { return }
        undoScene = nil
        apply(s)
        Toast.shared.show("Put the desk back", duration: 2)
    }

    /// Windows the last `apply` moved off a display that isn't connected (SO-056).
    private(set) static var folded = 0

    /// Core of restore; returns windows that couldn't be matched.
    @discardableResult
    static func apply(_ scene: StageScene) -> Outcome {
        let c = StageController.shared
        folded = 0
        let flat: [(group: Int, window: StageScene.Window)] = scene.groups.enumerated().flatMap { gi, g in g.windows.map { (group: gi, window: $0) } }
        let live = c.inventory.windows.map(\.snapshot)
        let result = IdentityMatcher.match(saved: flat.map(\.window), live: live)

        var desk = Desk()
        var groupIDs: [UUID] = []
        for g in scene.groups {
            // A group pinned to a display that isn't connected folds onto the others.
            let pinned = g.display.flatMap { Displays.screen(withID: $0) == nil ? nil : $0 }
            var group = StageGroup(name: g.name, color: g.color, layout: g.layout, displayID: pinned)
            group.windowIDs = []
            desk.groups.append(group)
            groupIDs.append(group.id)
        }
        var targetFrame: [CGWindowID: CGRect] = [:]
        for m in result.matches {
            let (gi, w) = flat[m.savedIndex]
            desk.groups[gi].windowIDs.append(m.windowID)
            targetFrame[m.windowID] = reflowed(w.cgFrame, scene: scene, display: scene.groups[gi].display)
        }
        if !result.unmatchedLive.isEmpty {
            desk.groups.append(StageGroup(name: "Other", color: GroupColor.palette.last ?? "#b9bcc7", windowIDs: result.unmatchedLive))
        }
        let activeIndex = min(max(0, scene.active), max(0, desk.groups.count - 1))
        desk.activeID = desk.groups.indices.contains(activeIndex) ? desk.groups[activeIndex].id : desk.groups.first?.id

        // Apply placement preferences the scene was saved with (first display).
        if let d = scene.displays.first {
            let prefs = Preferences.shared
            if prefs.stripEdge != d.strip { prefs.stripEdge = d.strip }
            if prefs.overlapMode != d.mode { prefs.overlapMode = d.mode }
            if prefs.stripSize != d.size { prefs.stripSize = d.size }
        }

        // Park everything that's off stage at its target frame, place on-stage windows.
        let activeIDs = Set(desk.active?.windowIDs ?? [])
        for w in c.inventory.windows {
            let target = targetFrame[w.id]
            if activeIDs.contains(w.id) {
                if c.parking.isParked(w.id) { c.parking.unpark(w, to: target) }
                else if let target { c.mover.animate(w, to: target, duration: 0.42) }
            } else {
                if !c.parking.isParked(w.id) { c.parking.park(w) }
                if let target { c.parking.setSavedFrame(w.id, target) }
            }
        }
        c.mutateDesk { $0 = desk }
        c.raiseActive()
        let missing = result.unmatchedSaved.map { flat[$0] }
        return Outcome(placed: result.matches.count, missing: missing)
    }

    /// SO-035: map a saved frame from the usable area it was saved in to today's.
    static func reflowed(_ frame: CGRect, scene: StageScene, display: String?) -> CGRect {
        // SO-056: the window's own saved display (its group's, or the one it sat on).
        let own = display.flatMap { id in scene.displays.first { $0.id == id } } ?? DisplayFold.display(of: frame, in: scene.displays)
        if scene.displays.count > 1, let own, Displays.screen(withID: own.id) == nil,
           let main = ScreenLayouts.current()?.usableFrame {
            folded += 1
            let old = own.usable.map { CGRect(array: $0) } ?? CGRect(array: own.frame)
            return DisplayFold.fold(frame, from: old, to: main)
        }
        let saved = own ?? scene.displays.first
        let now = (display.flatMap { Displays.screen(withID: $0) }).flatMap { ScreenLayouts.current(for: $0) }
            ?? ScreenLayouts.layout(containing: frame) ?? ScreenLayouts.current()
        guard let now else { return frame }
        guard let old = saved?.usable.map({ CGRect(array: $0) }) else { return frame.clamped(to: now.usableFrame) }
        return old == now.usableFrame ? frame.clamped(to: now.usableFrame) : Reflow.remap(frame, from: old, to: now.usableFrame)
    }
}

/// "Never lose a desk": the desk autosaves, and after a restart (when every saved window
/// id is gone) the last session is restored by identity without relaunching apps.
@MainActor
enum SessionAutosave {
    static var file: URL { IPC.supportDirectory.appendingPathComponent("last-session.stagescene") }
    private static var pending: DispatchWorkItem?
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        StageController.shared.onDeskChange.append { SessionAutosave.schedule() }
    }

    static func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { SessionAutosave.saveNow() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    static func saveNow() {
        let c = StageController.shared
        guard c.isRunning, !c.inventory.windows.isEmpty else { return }
        let scene = Scenes.capture(name: "Last session")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? scene.encoded().write(to: file, options: .atomic)
    }

    static func lastSession() -> StageScene? {
        (try? Data(contentsOf: file)).flatMap { try? StageScene.decode($0) }
    }
}
