import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// Borderless, non-activating panel that hosts the strip on one display.
@MainActor
final class StripPanel: NSPanel {
    init(rootView: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // No .fullScreenAuxiliary: like Stage Manager, the strip stays out of full screen apps.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Places the panel over a lane given in top-left global space.
    func place(lane: CGRect) {
        let appKitFrame = CoordinateSpace.flip(lane, primaryHeight: Displays.primaryHeight)
        setFrame(appKitFrame, display: true)
    }
}

/// Owns the strip panels (one on the main display for now) and keeps them placed.
@MainActor
final class StripManager {
    static let shared = StripManager()
    private var panel: StripPanel?
    let model = StripModel()
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard panel == nil else { return }
        let p = StripPanel(rootView: StripView(model: model, controller: StageController.shared, prefs: Preferences.shared))
        panel = p
        layout()
        p.orderFrontRegardless()
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StripManager.shared.layout() }
        })
    }

    func stop() {
        panel?.orderOut(nil)
        panel = nil
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }

    /// The panel's frame in AppKit screen coordinates.
    var panelFrame: CGRect? { panel?.frame }

    func setVisible(_ visible: Bool) {
        if visible { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
    }

    /// The strip's screen layout on the main display.
    var screenLayout: ScreenLayout? { ScreenLayouts.current() }

    func layout() {
        guard let panel, let l = screenLayout else { return }
        model.edge = l.stripEdge
        model.size = l.size
        panel.place(lane: hidden ? StripVisibility.hiddenLane(l.lane, edge: l.stripEdge) : l.lane)
    }

    /// SO-032: true while the strip is slid off and faded out.
    private(set) var hidden = false

    /// Slides the strip 40pt toward its edge and fades it (or brings it back).
    /// While hidden it lets clicks through to the windows underneath.
    func setHidden(_ hide: Bool, animated: Bool) {
        hidden = hide
        guard let panel, let l = screenLayout else { return }
        let lane = hide ? StripVisibility.hiddenLane(l.lane, edge: l.stripEdge) : l.lane
        let frame = CoordinateSpace.flip(lane, primaryHeight: Displays.primaryHeight)
        panel.ignoresMouseEvents = hide
        let motion = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if motion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = hide ? 0.22 : 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = hide ? 0 : 1
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = hide ? 0 : 1
        }
    }
}

/// Builds `ScreenLayout`s from the current screens and preferences.
@MainActor
enum ScreenLayouts {
    static func current(for screen: NSScreen? = NSScreen.screens.first) -> ScreenLayout? {
        guard let screen else { return nil }
        let prefs = Preferences.shared
        return ScreenLayout(displayID: Displays.stableID(of: screen),
                            frame: Displays.frame(of: screen),
                            visibleFrame: Displays.visibleFrame(of: screen),
                            stripEdge: prefs.stripEdge,
                            dockEdge: Displays.dockEdge,
                            mode: prefs.overlapMode,
                            size: prefs.stripSize)
    }

    static func all() -> [ScreenLayout] { NSScreen.screens.compactMap { current(for: $0) } }

    /// The layout of the display holding `rect`, defaulting to the main display.
    static func layout(containing rect: CGRect) -> ScreenLayout? {
        current(for: Displays.screen(for: rect) ?? NSScreen.screens.first)
    }
}

@MainActor
final class StripModel: ObservableObject {
    @Published var edge: ScreenEdge = .left
    @Published var size: StripSize = .full
    /// Shows ⌥ number badges while Option is held (SO-021).
    @Published var showNumbers = false
    /// SO-024: the strip's search text (shown with more than 8 groups).
    @Published var query = ""
    /// Group currently highlighted as a drop target (SO-022).
    @Published var dropTarget: UUID?
    @Published var dropOnNew = false
    /// A window drag is in progress (shows the "+ New group" slot).
    @Published var dragging = false
    /// Tile frames in panel-local, top-left coordinates, for drop hit-testing.
    var tileFrames: [UUID: CGRect] = [:]
    var newSlotFrame: CGRect?
    /// Group being dragged to reorder the strip.
    var reordering: UUID?
}
