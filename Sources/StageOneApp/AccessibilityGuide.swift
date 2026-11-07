import AppKit
import StageOneCore
import SwiftUI
import WindowKit

/// SO-136: one-drag Accessibility setup. Opens Privacy & Security › Accessibility and floats a
/// small tile beside the System Settings window. Dragging the tile into the list adds Stage One
/// and switches it on in one go, so nobody has to hunt for it in a long list. The tile follows the
/// Settings window, closes when Settings closes, and calls back the moment access is granted.
@MainActor
final class AccessibilityGuide {
    static let shared = AccessibilityGuide()

    private var panel: GuidePanel?
    private var model = GuideModel()
    private var timer: Timer?
    private var onGranted: [() -> Void] = []
    /// Seen the Settings window at least once, so its absence now means the user closed it.
    private var sawSettings = false
    private var startedAt = Date()
    private var grantedAt: Date?

    static let size = CGSize(width: 300, height: 236)

    var isShowing: Bool { timer != nil }

    /// Opens Settings at the Accessibility list and shows the tile next to it.
    /// `granted` runs once, as soon as macOS reports Stage One as trusted.
    func show(granted: (() -> Void)? = nil) {
        if let granted { onGranted.append(granted) }
        if Permissions.accessibility {
            finish(granted: true)
            return
        }
        Permissions.openAccessibilitySettings()
        sawSettings = false
        grantedAt = nil
        startedAt = Date()
        model.allowed = false
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func close() {
        finish(granted: Permissions.accessibility)
    }

    private func tick() {
        if Permissions.accessibility {
            // Show the "Allowed" state for a beat before getting out of the way.
            if grantedAt == nil {
                grantedAt = Date()
                model.allowed = true
                Engine.startIfReady()
            } else if let at = grantedAt, Date().timeIntervalSince(at) > 0.9 {
                finish(granted: true)
            }
            return
        }
        guard let settings = Self.settingsWindowFrame() else {
            // Settings closed (or never opened): put the tile away.
            if sawSettings || Date().timeIntervalSince(startedAt) > 8 { finish(granted: false) } else { panel?.orderOut(nil) }
            return
        }
        sawSettings = true
        let screens = NSScreen.screens.map { CoordinateSpace.flip($0.visibleFrame, primaryHeight: Self.primaryHeight) }
        guard let screen = PermissionGuide.screen(for: settings, among: screens) else { return }
        let placement = PermissionGuide.place(guide: Self.size, beside: settings, on: screen)
        if model.side != placement.side { model.side = placement.side }
        let p = panel ?? makePanel()
        let frame = CoordinateSpace.flip(placement.frame, primaryHeight: Self.primaryHeight)
        if p.frame != frame { p.setFrame(frame, display: true) }
        if !p.isVisible { p.orderFrontRegardless() }
    }

    private func finish(granted: Bool) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        let callbacks = onGranted
        onGranted = []
        if granted {
            Engine.startIfReady()
            callbacks.forEach { $0() }
        }
    }

    private func makePanel() -> GuidePanel {
        let p = GuidePanel(contentRect: NSRect(origin: .zero, size: Self.size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.appearance = NSAppearance(named: .aqua)
        p.isReleasedWhenClosed = false
        let host = FirstClickHostingView(rootView: GuideView(model: model) { [weak self] in self?.close() })
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        panel = p
        return p
    }

    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// The System Settings window, in the top-left global space.
    private static func settingsWindowFrame() -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let settingsPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .map(\.processIdentifier))
        guard !settingsPIDs.isEmpty else { return nil }
        let entries: [PermissionGuide.WindowEntry] = info.compactMap { row in
            guard let pid = row[kCGWindowOwnerPID as String] as? pid_t, settingsPIDs.contains(pid),
                  let layer = row[kCGWindowLayer as String] as? Int,
                  let dict = row[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return .init(owner: "com.apple.systempreferences", layer: layer, bounds: bounds)
        }
        return PermissionGuide.settingsWindow(in: entries)
    }
}

@MainActor
private final class GuideModel: ObservableObject {
    @Published var side: PermissionGuide.Side = .right
    @Published var allowed = false
}

/// Never takes focus from System Settings, so the user's drag lands where they expect.
private final class GuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clicks on the tile work even though Stage One is not the active app.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Views

private struct GuideView: View {
    @ObservedObject var model: GuideModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if model.side == .right { GuideArrow(pointsLeft: true) }
                Text(model.allowed ? "Allowed" : "Drag Stage One into the list")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if model.side == .left { GuideArrow(pointsLeft: false) }
                Button(action: onClose) {
                    Text("×").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink3)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            if model.allowed {
                HStack(spacing: 12) {
                    MarkView(size: 34)
                    Text("Stage One can arrange your windows now.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                AppTile()
                    .frame(height: 64)
                Text("Already in the list? Just switch it on. If the switch is on but nothing happens, select Stage One, click −, then drag this tile in again.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: AccessibilityGuide.size.width, height: AccessibilityGuide.size.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: 0xfffdfb))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line)
        )
        .preferredColorScheme(.light)
        .animation(.easeOut(duration: 0.18), value: model.allowed)
    }
}

/// A short orange arrow pointing at System Settings, nudging gently.
private struct GuideArrow: View {
    let pointsLeft: Bool
    @State private var nudge = false

    var body: some View {
        ArrowShape()
            .stroke(Theme.spot, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .frame(width: 22, height: 14)
            .scaleEffect(x: pointsLeft ? 1 : -1, y: 1)
            .offset(x: nudge ? (pointsLeft ? -4 : 4) : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { nudge = true }
            }
    }
}

/// Left-pointing arrow.
private struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.move(to: CGPoint(x: r.minX + r.height / 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.height / 2, y: r.maxY))
        return p
    }
}

private struct AppTile: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragTile { AppDragTile() }
    func updateNSView(_ nsView: AppDragTile, context: Context) {}
}

/// The draggable "Stage One" tile. It drags the app bundle's file URL, which is exactly what
/// System Settings accepts when an app is dropped onto its Accessibility list.
final class AppDragTile: NSView, NSDraggingSource {
    private let appURL = Bundle.main.bundleURL
    private lazy var icon: NSImage = NSWorkspace.shared.icon(forFile: appURL.path)
    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Stage One"
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        NSColor(srgbRed: 0xfd / 255, green: 0xe3 / 255, blue: 0xd2 / 255, alpha: 0.55).setFill()
        shape.fill()
        Theme.nsSpot.setStroke()
        shape.lineWidth = 1.5
        shape.setLineDash([5, 4], count: 2, phase: 0)
        shape.stroke()

        let side = min(44, r.height - 16)
        let iconRect = NSRect(x: r.minX + 12, y: r.midY - side / 2, width: side, height: side)
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let ink = NSColor(srgbRed: 0x20 / 255, green: 0x22 / 255, blue: 0x2b / 255, alpha: 1)
        let ink3 = NSColor(srgbRed: 0x8b / 255, green: 0x8d / 255, blue: 0x98 / 255, alpha: 1)
        let x = iconRect.maxX + 12
        (appName as NSString).draw(at: NSPoint(x: x, y: r.midY - 18),
                                   withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                                                    .foregroundColor: ink])
        ("Drag me onto the list" as NSString).draw(at: NSPoint(x: x, y: r.midY + 2),
                                                    withAttributes: [.font: NSFont.systemFont(ofSize: 11.5),
                                                                     .foregroundColor: ink3])
    }

    override func mouseDown(with event: NSEvent) {
        // Swallow it so the drag starts here instead of moving the panel.
    }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let p = convert(event.locationInWindow, from: nil)
        let side: CGFloat = 48
        item.setDraggingFrame(NSRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side), contents: icon)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic, .link] : []
    }
}
