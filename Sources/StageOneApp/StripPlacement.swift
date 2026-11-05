import AppKit
import Combine
import StageOneCore
import WindowKit

/// SO-030: the strip can sit on any edge, whatever side the Dock is on. On the Dock's
/// edge it sits just inside the Dock (the visible frame already excludes it), and it
/// re-places itself when the Dock auto-hides, resizes or moves.
@MainActor
final class StripPlacement {
    static let shared = StripPlacement()
    private var bag: Set<AnyCancellable> = []
    private var dockTimer: Timer?
    private var lastDock: (ScreenEdge, CGRect)?
    /// Called after the placement changed, with the usable areas before and after (per display).
    var onPlacementChange: [([String: CGRect], [String: CGRect]) -> Void] = []
    private var lastUsable: [String: CGRect] = [:]

    func install() {
        guard bag.isEmpty else { return }
        lastUsable = Self.usableAreas()
        let prefs = Preferences.shared
        prefs.$stripEdge.dropFirst().sink { _ in Self.later { StripPlacement.shared.changed() } }.store(in: &bag)
        prefs.$overlapMode.dropFirst().sink { _ in Self.later { StripPlacement.shared.changed() } }.store(in: &bag)
        prefs.$stripSize.dropFirst().sink { _ in Self.later { StripPlacement.shared.changed() } }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { _ in Self.later { StripPlacement.shared.changed() } }
            .store(in: &bag)
        // The Dock's orientation and auto-hide don't always post screen-parameter changes;
        // a cheap poll of the visible frame catches them.
        dockTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { StripPlacement.shared.checkDock() }
        }
        dockTimer?.tolerance = 1
    }

    func uninstall() {
        bag.removeAll()
        dockTimer?.invalidate()
        dockTimer = nil
    }

    /// Runs after the @Published value has been stored.
    private static func later(_ f: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { f() } }
    }

    private func checkDock() {
        guard let screen = NSScreen.screens.first else { return }
        let now = (Displays.dockEdge, Displays.visibleFrame(of: screen))
        if let last = lastDock, last.0 == now.0, last.1 == now.1 { return }
        let first = lastDock == nil
        lastDock = now
        if !first { changed() }
    }

    func changed() {
        StripManager.shared.layout()
        let new = Self.usableAreas()
        let old = lastUsable
        lastUsable = new
        if old != new { onPlacementChange.forEach { $0(old, new) } }
    }

    static func usableAreas() -> [String: CGRect] {
        Dictionary(ScreenLayouts.all().map { ($0.displayID, $0.usableFrame) }, uniquingKeysWith: { a, _ in a })
    }
}
