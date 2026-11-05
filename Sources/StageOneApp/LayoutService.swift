import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// SO-040: per-stage layouts (Free, Halves, Main + side, Thirds, Grid) with an 8px gap
/// inside the usable area. Each group remembers its layout.
@MainActor
enum LayoutService {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        // Groups coming on stage take their layout's frames.
        StageController.shared.layoutFrame = { id, group in
            frames(for: group)[id]
        }
        LayoutBar.shared.install()
    }

    static func uninstall() {
        LayoutBar.shared.uninstall()
    }

    /// The usable area a group lives in: its display, or the display holding its front window.
    static func usableArea(for group: StageGroup) -> CGRect? {
        let c = StageController.shared
        if let id = group.displayID, let screen = Displays.screen(withID: id) {
            return ScreenLayouts.current(for: screen)?.usableFrame
        }
        let front = group.windowIDs.first.flatMap { c.parking.savedFrame($0) ?? c.inventory[$0]?.frame }
        return (front.flatMap { ScreenLayouts.layout(containing: $0) } ?? ScreenLayouts.current())?.usableFrame
    }

    /// Target frames for every window of a group under its layout (empty for Free).
    static func frames(for group: StageGroup) -> [CGWindowID: CGRect] {
        let c = StageController.shared
        let ids = group.windowIDs.filter { c.inventory[$0] != nil }
        guard let area = usableArea(for: group),
              let rects = LayoutEngine.frames(for: group.layout, count: ids.count, in: area) else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(ids, rects))
    }

    /// Sets the active group's layout and arranges its windows (animated 450ms).
    static func apply(_ kind: LayoutKind) {
        let c = StageController.shared
        guard let gid = c.desk.activeID else { return }
        c.mutateDesk { d in if let i = d.groups.firstIndex(where: { $0.id == gid }) { d.groups[i].layout = kind } }
        arrangeActive()
        Toast.shared.show("Layout: \(kind.title)", duration: 1.6)
    }

    static func arrangeActive(animated: Bool = true) {
        let c = StageController.shared
        guard let g = c.desk.active else { return }
        for (id, frame) in frames(for: g) {
            guard let w = c.inventory[id], !c.parking.isParked(id) else { continue }
            if animated { c.mover.animate(w, to: frame, duration: 0.45) } else { c.mover.setFrame(w, frame) }
        }
    }
}

/// The layout bar that slides down when the pointer reaches the top of the stage area.
@MainActor
final class LayoutBar {
    static let shared = LayoutBar()
    private var panel: NSPanel?
    private var monitor: Any?
    private var hideWork: DispatchWorkItem?
    private let model = LayoutBarModel()

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            MainActor.assumeIsolated { LayoutBar.shared.pointerMoved() }
        }
    }

    func uninstall() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        panel?.orderOut(nil)
    }

    private func pointerMoved() {
        guard let screen = NSScreen.screens.first, let layout = ScreenLayouts.current(for: screen) else { return }
        let p = NSEvent.mouseLocation
        let top = CGPoint(x: p.x, y: Displays.primaryHeight - p.y) // top-left space
        let u = layout.usableFrame
        let inTrigger = top.y >= u.minY - 2 && top.y <= u.minY + 4 && top.x > u.minX + u.width * 0.25 && top.x < u.maxX - u.width * 0.25
        if inTrigger {
            show(in: u)
        } else if let panel, panel.isVisible, !panel.frame.insetBy(dx: -20, dy: -20).contains(p) {
            scheduleHide()
        }
    }

    private func show(in usable: CGRect) {
        hideWork?.cancel()
        model.current = StageController.shared.desk.active?.layout ?? .free
        let p = panel ?? makePanel()
        panel = p
        let size = CGSize(width: 360, height: 52)
        let topLeft = CGRect(x: usable.midX - size.width / 2, y: usable.minY + 6, width: size.width, height: size.height)
        p.setFrame(CoordinateSpace.flip(topLeft, primaryHeight: Displays.primaryHeight), display: true)
        if !p.isVisible {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                p.animator().alphaValue = 1
            }
        }
    }

    private func scheduleHide() {
        guard hideWork == nil || hideWork!.isCancelled else { return }
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                LayoutBar.shared.panel?.orderOut(nil)
                LayoutBar.shared.hideWork = nil
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.appearance = NSAppearance(named: .aqua)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: LayoutBarView(model: model))
        return p
    }
}

@MainActor
final class LayoutBarModel: ObservableObject {
    @Published var current: LayoutKind = .free
}

struct LayoutBarView: View {
    @ObservedObject var model: LayoutBarModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LayoutKind.allCases, id: \.self) { kind in
                Button {
                    model.current = kind
                    LayoutService.apply(kind)
                } label: {
                    VStack(spacing: 2) {
                        LayoutGlyph(kind: kind, active: model.current == kind).frame(width: 30, height: 20)
                        Text(kind.title).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(model.current == kind ? Theme.spot : Theme.ink2)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.current == kind ? Theme.spotSoft : .clear))
                }
                .buttonStyle(.plain)
                .help(kind.title)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        .environment(\.colorScheme, .light)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Tiny schematic of a layout.
struct LayoutGlyph: View {
    let kind: LayoutKind
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(origin: .zero, size: geo.size)
            let rects = LayoutEngine.frames(for: kind, count: kind == .grid ? 4 : (kind == .thirds ? 3 : (kind == .focus ? 3 : 2)), in: area, gap: 2)
                ?? [area.insetBy(dx: 5, dy: 3), area.insetBy(dx: 2, dy: 6).offsetBy(dx: 4, dy: 3)]
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(active ? Theme.spot : Theme.ink3.opacity(0.6))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }
}
