import AppKit
import Combine
import StageOneCore
import WindowKit

/// SO-032 / SO-033: hides and reveals the strip in "Can overlap" and "Auto-hide" modes.
/// Event driven: pointer moves and window moves trigger a check, plus one timer for the
/// hide delay. Nothing runs in "Never overlap" mode.
@MainActor
final class StripAutoHide {
    static let shared = StripAutoHide()
    private var state = StripVisibility()
    private var monitors: [Any] = []
    private var bag: Set<AnyCancellable> = []
    private var recheck: Timer?
    private var installed = false

    func install() {
        guard !installed else { return }
        installed = true
        StageController.shared.onWindowEvent.append { e in
            switch e {
            case .moved, .resized, .focused, .created, .destroyed: StripAutoHide.shared.evaluate()
            default: break
            }
        }
        StageController.shared.onDeskChange.append { StripAutoHide.shared.evaluate() }
        Preferences.shared.$overlapMode.sink { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { StripAutoHide.shared.modeChanged() } }
        }.store(in: &bag)
        modeChanged()
    }

    func uninstall() {
        stopMonitoring()
        bag.removeAll()
        installed = false
        state = StripVisibility()
        StripManager.shared.setHidden(false, animated: false)
    }

    private func modeChanged() {
        if Preferences.shared.overlapMode == .reserve {
            stopMonitoring()
            state = StripVisibility()
            StripManager.shared.setHidden(false, animated: true)
        } else {
            startMonitoring()
            evaluate()
        }
    }

    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            MainActor.assumeIsolated { StripAutoHide.shared.evaluate() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in
            MainActor.assumeIsolated { StripAutoHide.shared.evaluate() }
            return e
        }) { monitors.append(l) }
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        recheck?.invalidate()
        recheck = nil
    }

    func evaluate() {
        let prefs = Preferences.shared
        guard installed, prefs.overlapMode != .reserve, let layout = StripManager.shared.screenLayout else { return }
        let c = StageController.shared
        let lane = layout.lane
        let frames = (c.desk.active?.windowIDs ?? []).compactMap { id -> CGRect? in
            guard let w = c.inventory[id], !c.parking.isParked(id) else { return nil }
            return w.frame
        }
        let m = NSEvent.mouseLocation
        let pointer = CGPoint(x: m.x, y: Displays.primaryHeight - m.y)
        let now = CFAbsoluteTimeGetCurrent()
        let wasShown = state.shown
        let shown = state.update(mode: prefs.overlapMode,
                                 windowsTouchLane: StripVisibility.windowsTouch(frames, lane: lane),
                                 pointerAtEdge: StripVisibility.pointerAtEdge(pointer, lane: lane, edge: layout.stripEdge),
                                 pointerInLane: lane.contains(pointer),
                                 now: now)
        if shown != wasShown { StripManager.shared.setHidden(!shown, animated: true) }
        recheck?.invalidate()
        recheck = nil
        if let at = state.recheckAt {
            let t = Timer(timeInterval: max(0.05, at - now + 0.02), repeats: false) { _ in
                MainActor.assumeIsolated { StripAutoHide.shared.evaluate() }
            }
            RunLoop.main.add(t, forMode: .common)
            recheck = t
        }
    }
}
