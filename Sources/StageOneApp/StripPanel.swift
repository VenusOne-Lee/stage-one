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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
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

    func setVisible(_ visible: Bool) {
        if visible { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
    }

    /// The strip's screen layout on the main display.
    var screenLayout: ScreenLayout? { ScreenLayouts.current() }

    func layout() {
        guard let panel, let l = screenLayout else { return }
        model.edge = l.stripEdge
        model.size = l.size
        panel.place(lane: l.lane)
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
    /// Group currently highlighted as a drop target (SO-022).
    @Published var dropTarget: UUID?
    @Published var dropOnNew = false
}
