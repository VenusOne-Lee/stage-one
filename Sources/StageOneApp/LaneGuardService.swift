import AppKit
import StageOneCore
import WindowKit

/// SO-031: Never overlap. Any on-stage window that moves, resizes or opens inside the
/// strip's lane is moved out (or shrunk to fit) within 100ms: animated, unless the
/// user is mid-drag, in which case it is corrected on mouse-up. Zoom and the green
/// button's fill land in the usable area because the result is clamped the same way.
@MainActor
final class LaneGuardService {
    static let shared = LaneGuardService()
    private var installed = false
    private var pending: Set<CGWindowID> = []
    private var mouseUp: Any?

    func install() {
        guard !installed else { return }
        installed = true
        StageController.shared.onWindowEvent.append { e in
            switch e {
            case .moved(let id), .resized(let id), .created(let id):
                LaneGuardService.shared.check(id)
            default:
                break
            }
        }
        mouseUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            MainActor.assumeIsolated { LaneGuardService.shared.flush() }
        }
    }

    func uninstall() {
        if let m = mouseUp { NSEvent.removeMonitor(m) }
        mouseUp = nil
        installed = false
        pending.removeAll()
    }

    func check(_ id: CGWindowID) {
        let c = StageController.shared
        guard Preferences.shared.overlapMode == .reserve, !c.isSwitching, !c.parking.isParked(id),
              let w = c.inventory[id] else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            pending.insert(id)
            return
        }
        correct(w, animated: true)
    }

    /// Mouse released: fix anything that ended up in the lane, unless it was dropped on a group.
    private func flush() {
        let ids = pending
        pending.removeAll()
        // Let DragToGroup handle its drop first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            MainActor.assumeIsolated {
                let c = StageController.shared
                for id in ids {
                    guard let w = c.inventory[id], !c.parking.isParked(id) else { continue }
                    LaneGuardService.shared.correct(w, animated: true)
                }
            }
        }
    }

    /// Checks every on-stage window (after placement changes or a scene restore).
    func sweep(animated: Bool = true) {
        let c = StageController.shared
        guard Preferences.shared.overlapMode == .reserve else { return }
        for id in c.desk.active?.windowIDs ?? [] {
            if let w = c.inventory[id], !c.parking.isParked(id) { correct(w, animated: animated) }
        }
    }

    private func correct(_ w: TrackedWindow, animated: Bool) {
        let frame = w.liveFrame() ?? w.frame
        guard !Parking.looksParked(frame), let layout = ScreenLayouts.layout(containing: frame),
              let fixed = LaneGuard.correction(for: frame, in: layout, minSize: w.learnedMinSize) else { return }
        if animated {
            StageController.shared.mover.animate(w, to: fixed, duration: 0.2)
        } else {
            StageController.shared.mover.setFrame(w, fixed)
        }
    }
}
