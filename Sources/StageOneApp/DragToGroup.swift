import AppKit
import StageOneCore
import WindowKit

/// SO-022: drag a window's title bar over a strip group to move it into that group.
@MainActor
final class DragToGroup {
    static let shared = DragToGroup()

    private var installed = false
    private var monitors: [Any] = []
    private var dragged: CGWindowID?
    private var preDragFrame: CGRect?
    private var model: StripModel { StripManager.shared.model }

    /// True while a dragged window hovers a drop target; the lane guard waits then.
    var isHoveringStrip: Bool { dragged != nil && (model.dropTarget != nil || model.dropOnNew) }
    var isDragging: Bool { dragged != nil }

    func install() {
        guard !installed else { return }
        installed = true
        StageController.shared.onWindowEvent.append { e in
            if case .moved(let id) = e { DragToGroup.shared.windowMoved(id) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { _ in
            MainActor.assumeIsolated { DragToGroup.shared.update() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in
            MainActor.assumeIsolated { DragToGroup.shared.end() }
        }) { monitors.append(m) }
    }

    func uninstall() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        installed = false
        cancel()
    }

    private func windowMoved(_ id: CGWindowID) {
        let c = StageController.shared
        guard NSEvent.pressedMouseButtons & 1 != 0, !c.isSwitching, dragged == nil,
              let w = c.inventory[id], !c.parking.isParked(id) else { return }
        dragged = id
        preDragFrame = w.previousFrame ?? w.frame
        model.dragging = true
        update()
    }

    private func update() {
        guard dragged != nil, let panel = StripManager.shared.panelFrame else { return }
        let p = NSEvent.mouseLocation
        // Panel-local, top-left origin (SwiftUI's global space inside the hosting view).
        let local = CGPoint(x: p.x - panel.minX, y: panel.maxY - p.y)
        let hit = model.tileFrames.first { $0.value.insetBy(dx: -8, dy: -8).contains(local) }?.key
        let onNew = hit == nil && (model.newSlotFrame?.insetBy(dx: -8, dy: -8).contains(local) ?? false)
        if model.dropTarget != hit { model.dropTarget = hit }
        if model.dropOnNew != onNew { model.dropOnNew = onNew }
    }

    private func end() {
        guard let id = dragged else { return }
        let c = StageController.shared
        let target = model.dropTarget, onNew = model.dropOnNew
        let fromGroup = c.desk.group(containing: id)?.id
        let restore = preDragFrame
        cancel()
        guard target != nil || onNew, let w = c.inventory[id] else { return }
        // Put the window back where the drag started, so it returns there later.
        if let restore { c.mover.setFrame(w, restore) }
        let name: String
        if let target {
            c.move(window: id, to: target)
            name = c.desk.groups.first { $0.id == target }?.name ?? "group"
        } else {
            let g = c.newGroup(with: id)
            name = c.desk.groups.first { $0.id == g }?.name ?? "new group"
        }
        Toast.shared.show("Moved “\(w.title.isEmpty ? w.snapshot.appName : w.title)” to \(name)", action: (title: "Undo", run: {
            if let fromGroup { StageController.shared.move(window: id, to: fromGroup) }
        }))
    }

    private func cancel() {
        dragged = nil
        preDragFrame = nil
        model.dragging = false
        model.dropTarget = nil
        model.dropOnNew = false
    }
}
