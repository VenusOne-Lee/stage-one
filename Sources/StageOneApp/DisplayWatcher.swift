import AppKit
import CoreGraphics
import StageOneCore
import WindowKit

/// SO-071: display rules through `CGDisplayRegisterReconfigurationCallback`. Plugging in or
/// unplugging posts display rule events. Unplugging folds every group that lived on the
/// lost display onto the remaining screen, keeping window sizes.
@MainActor
enum DisplayWatcher {
    private static var installed = false
    private static var known: [String: CGRect] = [:]   // stable id → usable area
    private static var pending: DispatchWorkItem?

    static func install() {
        guard !installed else { return }
        installed = true
        known = StripPlacement.usableAreas()
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil)
    }

    static func uninstall() {
        guard installed else { return }
        installed = false
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, nil)
        pending?.cancel()
    }

    /// Several callbacks arrive per change (one per display); settle first.
    fileprivate static func reconfigured() {
        pending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { DisplayWatcher.settle() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private static func settle() {
        let now = StripPlacement.usableAreas()
        let removed = Set(known.keys).subtracting(now.keys)
        let added = Set(now.keys).subtracting(known.keys)
        let before = known
        known = now
        if !removed.isEmpty { fold(removed, before: before) }
        removed.sorted().forEach { RuleService.shared.post(.displayDisconnected($0)) }
        added.sorted().forEach { RuleService.shared.post(.displayConnected($0)) }
    }

    /// Groups on a lost display move to the main one: pins are dropped, and parked windows
    /// that would come back off-screen are folded into the main display's usable area.
    static func fold(_ removed: Set<String>, before: [String: CGRect]) {
        let c = StageController.shared
        guard c.isRunning, let main = ScreenLayouts.current()?.usableFrame else { return }
        c.mutateDesk { d in
            for i in d.groups.indices where d.groups[i].displayID.map(removed.contains) ?? false {
                d.groups[i].displayID = nil
            }
        }
        let screens = NSScreen.screens.map(Displays.frame(of:))
        var moved = 0
        for w in c.inventory.windows {
            guard let saved = c.parking.savedFrame(w.id),
                  !screens.contains(where: { $0.intersects(saved) }) else { continue }
            let old = before.first { removed.contains($0.key) && $0.value.insetBy(dx: -40, dy: -40).intersects(saved) }?.value
            c.parking.setSavedFrame(w.id, old.map { DisplayFold.fold(saved, from: $0, to: main) } ?? saved.clamped(to: main))
            moved += 1
        }
        if c.desk.active != nil { LayoutService.arrangeActive(animated: true) }
        if moved > 0 || !removed.isEmpty {
            Toast.shared.show("A display was unplugged",
                              detail: "Its groups moved to this screen at the same size\(moved > 0 ? " (\(moved) waiting off stage)" : "").",
                              duration: 4)
        }
    }
}

/// The C callback. Runs on the main thread in practice; hops there to be sure.
private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                 _ userInfo: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    DispatchQueue.main.async { MainActor.assumeIsolated { DisplayWatcher.reconfigured() } }
}
