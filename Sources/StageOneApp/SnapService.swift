import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// SO-041: dragging a window to the left or right edge of the usable area shows an orange
/// ghost and snaps to that half on release; the top edge fills the area.
@MainActor
final class SnapService {
    static let shared = SnapService()
    private var installed = false
    private var monitors: [Any] = []
    private var dragging: CGWindowID?
    private var zone: (SnapZone, CGRect)?
    private var ghost: NSPanel?

    func install() {
        guard !installed else { return }
        installed = true
        StageController.shared.onWindowEvent.append { e in
            if case .moved(let id) = e { SnapService.shared.moved(id) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { _ in
            MainActor.assumeIsolated { SnapService.shared.update() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            MainActor.assumeIsolated { SnapService.shared.release() }
        }) { monitors.append(m) }
    }

    func uninstall() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        installed = false
        hideGhost()
    }

    private func moved(_ id: CGWindowID) {
        let c = StageController.shared
        guard NSEvent.pressedMouseButtons & 1 != 0, !c.isSwitching, !c.parking.isParked(id) else { return }
        dragging = id
    }

    private func update() {
        guard dragging != nil else { return }
        if DragToGroup.shared.isHoveringStrip { hideGhost(); return }
        let p = NSEvent.mouseLocation
        let point = CGPoint(x: p.x, y: Displays.primaryHeight - p.y)
        guard let layout = ScreenLayouts.layout(containing: CGRect(origin: point, size: CGSize(width: 1, height: 1))) else { return }
        let usable = layout.usableFrame
        if let z = SnapZone.zone(for: point, in: usable) {
            let f = z.frame(in: usable)
            if zone?.1 != f { showGhost(f) }
            zone = (z, f)
        } else if zone != nil {
            zone = nil
            hideGhost()
        }
    }

    private func release() {
        defer { dragging = nil; zone = nil; hideGhost() }
        guard let id = dragging, let (_, frame) = zone, !DragToGroup.shared.isHoveringStrip,
              let w = StageController.shared.inventory[id] else { return }
        // Let the app finish its own drag first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { StageController.shared.mover.animate(w, to: frame, duration: 0.25) }
        }
    }

    private func showGhost(_ topLeftFrame: CGRect) {
        let g = ghost ?? makeGhost()
        ghost = g
        let target = CoordinateSpace.flip(topLeftFrame, primaryHeight: Displays.primaryHeight)
        if g.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                g.animator().setFrame(target, display: true)
            }
        } else {
            g.setFrame(target, display: true)
            g.alphaValue = 0
            g.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                g.animator().alphaValue = 1
            }
        }
    }

    private func hideGhost() { ghost?.orderOut(nil) }

    private func makeGhost() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: SnapGhost())
        return p
    }
}

struct SnapGhost: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.spot.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.spot.opacity(0.7), lineWidth: 2))
            .padding(2)
    }
}
