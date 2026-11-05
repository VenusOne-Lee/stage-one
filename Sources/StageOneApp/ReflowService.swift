import AppKit
import StageOneCore
import WindowKit

/// SO-035: when the strip edge, Dock side, mode or size changes, every window's frame is
/// remapped proportionally from the old usable area to the new one, then clamped.
/// Parked windows get their return frame remapped too.
@MainActor
enum ReflowService {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        StripPlacement.shared.onPlacementChange.append { old, new in
            ReflowService.reflow(from: old, to: new)
        }
    }

    static func reflow(from old: [String: CGRect], to new: [String: CGRect]) {
        let c = StageController.shared
        for w in c.inventory.windows {
            let parked = c.parking.isParked(w.id)
            let frame = parked ? (c.parking.savedFrame(w.id) ?? w.frame) : w.frame
            guard let display = Displays.screen(for: frame).map(Displays.stableID(of:)),
                  let o = old[display], let n = new[display], o != n else { continue }
            let target = Reflow.remap(frame, from: o, to: n)
            if parked {
                c.parking.setSavedFrame(w.id, target)
            } else {
                c.mover.animate(w, to: target, duration: 0.45)
            }
        }
    }
}
