import AppKit
import ScreenCaptureKit

/// Window thumbnails from ScreenCaptureKit (about 320px wide).
///
/// Uses desktop-independent window filters, so parked (off-screen) and covered windows
/// still capture. Without Screen Recording access it returns nothing and the strip
/// falls back to app icon tiles.
@MainActor
public final class Thumbnails: ObservableObject {
    @Published public private(set) var images: [CGWindowID: NSImage] = [:]
    public var width: CGFloat = 320
    private var inFlight = false
    /// True while the displays sleep or the user session is switched out (SO-130):
    /// nothing is visible, so capturing would only burn CPU.
    public private(set) var isSuspended = false
    private var tokens: [NSObjectProtocol] = []

    public init() {
        let nc = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        for (name, suspended) in pairs {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isSuspended = suspended }
            })
        }
    }

    public func image(for id: CGWindowID) -> NSImage? { images[id] }

    public func forget(_ ids: Set<CGWindowID>) {
        for id in ids { images[id] = nil }
    }

    /// Captures the given windows. Safe to call often; overlapping calls are dropped.
    public func capture(_ ids: [CGWindowID]) {
        guard !ids.isEmpty, !inFlight, !isSuspended, CGPreflightScreenCaptureAccess() else { return }
        inFlight = true
        let width = self.width
        Task { [weak self] in
            let result = await Self.grab(ids: ids, width: width)
            guard let self else { return }
            for (id, cg) in result.images {
                self.images[id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            self.inFlight = false
        }
    }

    struct Captured: @unchecked Sendable { var images: [CGWindowID: CGImage] = [:] }

    nonisolated static func grab(ids: [CGWindowID], width: CGFloat) async -> Captured {
        var out = Captured()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return out }
        let wanted = Set(ids)
        for w in content.windows where wanted.contains(w.windowID) {
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let config = SCStreamConfiguration()
            let scale = w.frame.width > 0 ? width / w.frame.width : 1
            config.width = max(16, Int(w.frame.width * scale * 2))
            config.height = max(16, Int(w.frame.height * scale * 2))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                out.images[w.windowID] = img
            }
        }
        return out
    }
}
