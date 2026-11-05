import AppKit
import ApplicationServices
import StageOneCore

/// A live window the inventory tracks. Holds the AX element used to move it.
@MainActor
public final class TrackedWindow: Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let element: AXUIElement
    public internal(set) var snapshot: WindowSnapshot
    /// The frame before the most recent move/resize event (used to undo drags).
    public internal(set) var previousFrame: CGRect?
    /// Minimum size learned from failed resizes (apps rarely report it).
    public var learnedMinSize: CGSize = .zero

    init(id: CGWindowID, pid: pid_t, element: AXUIElement, snapshot: WindowSnapshot) {
        self.id = id
        self.pid = pid
        self.element = element
        self.snapshot = snapshot
    }

    public var frame: CGRect { snapshot.frame }
    public var bundleID: String { snapshot.bundleID }
    public var title: String { snapshot.title }
    public var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }

    /// Reads the live frame from Accessibility (cheaper than a full refresh).
    public func liveFrame() -> CGRect? { AX.frame(element) }
}

public enum WindowEvent: Sendable {
    case created(CGWindowID)
    case destroyed(CGWindowID)
    case moved(CGWindowID)
    case resized(CGWindowID)
    case focused(CGWindowID)
    case titleChanged(CGWindowID)
    case appLaunched(pid_t)
    case appTerminated(pid_t)
}

/// SO-010: the live list of standard windows.
///
/// Enumerates with CGWindowList, matches each window to its AXUIElement by CGWindowID,
/// and stays current with AXObserver + NSWorkspace notifications. Idle cost is near zero:
/// it only rescans when an event arrives (coalesced), plus a slow safety rescan.
@MainActor
public final class WindowInventory: ObservableObject {
    /// Windows in front-to-back order.
    @Published public private(set) var windows: [TrackedWindow] = []
    public private(set) var byID: [CGWindowID: TrackedWindow] = [:]

    /// Called for every window event after the inventory has been updated.
    public var onEvent: ((WindowEvent) -> Void)?
    /// Called after each rescan.
    public var onChange: (() -> Void)?

    /// Bundle ids that are never managed.
    public var ignoredBundleIDs: Set<String> = [
        "com.apple.dock", "com.apple.notificationcenterui", "com.apple.controlcenter",
        "com.apple.WindowManager", "com.apple.Spotlight", "com.apple.systemuiserver",
        "com.apple.screencaptureui", "com.apple.loginwindow",
    ]

    private var observers: [pid_t: AppObserver] = [:]
    private var rescanScheduled = false
    private var safetyTimer: Timer?
    /// Hash of the last CGWindowList pass (ids, owners, bounds, on-screen), see `safetyRescan`.
    private var lastSignature: Int?
    private var workspaceTokens: [NSObjectProtocol] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init() {}

    public func start() {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.observe(pid: pid)
                self.scheduleRescan()
                self.onEvent?(.appLaunched(pid))
            }
        })
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.observers.removeValue(forKey: pid)?.invalidate()
                self.scheduleRescan()
                self.onEvent?(.appTerminated(pid))
            }
        })
        workspaceTokens.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRescan() }
        })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(pid: app.processIdentifier)
        }
        rescan()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.safetyRescan() }
        }
        safetyTimer?.tolerance = 2
    }

    public func stop() {
        safetyTimer?.invalidate()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        observers.values.forEach { $0.invalidate() }
        observers.removeAll()
    }

    public subscript(id: CGWindowID) -> TrackedWindow? { byID[id] }

    public var snapshots: [UInt32: WindowSnapshot] {
        Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.snapshot) })
    }

    /// Coalesces bursts of AX events into one rescan on the next runloop turn.
    public func scheduleRescan() {
        guard !rescanScheduled else { return }
        rescanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.rescanScheduled = false
                self?.rescan()
            }
        }
    }

    private static func windowList() -> [[String: Any]]? {
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
    }

    /// SO-130: a cheap fingerprint of the layer-0 window list. Same value means no window
    /// appeared, closed, moved, resized or changed visibility since the last scan.
    static func signature(of info: [[String: Any]]) -> Int {
        var h = Hasher()
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            h.combine(id)
            h.combine(w[kCGWindowOwnerPID as String] as? pid_t ?? 0)
            h.combine(w[kCGWindowIsOnscreen as String] as? Bool ?? false)
            h.combine(w[kCGWindowAlpha as String] as? Double ?? 1)
            if let d = w[kCGWindowBounds as String] as? NSDictionary,
               let r = CGRect(dictionaryRepresentation: d as CFDictionary) {
                h.combine(r.minX); h.combine(r.minY); h.combine(r.width); h.combine(r.height)
            }
        }
        return h.finalize()
    }

    /// The periodic safety net: skips all Accessibility work when CGWindowList is unchanged.
    /// Titles and focus still update through AX notifications.
    public func safetyRescan() {
        guard AXIsProcessTrusted(), let info = Self.windowList() else { return }
        if let last = lastSignature, last == Self.signature(of: info) { return }
        rescan(using: info)
    }

    /// Full rescan. Keeps existing TrackedWindow objects so identities stay stable.
    public func rescan() {
        guard AXIsProcessTrusted(), let info = Self.windowList() else { return }
        rescan(using: info)
    }

    private func rescan(using info: [[String: Any]]) {
        lastSignature = Self.signature(of: info)

        // CG order is front to back; keep it so stacking order is known.
        var order: [CGWindowID] = []
        var pids = Set<pid_t>()
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            order.append(id)
            pids.insert(pid)
        }

        var found: [CGWindowID: TrackedWindow] = [:]
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let bundle = app.bundleIdentifier, !ignoredBundleIDs.contains(bundle) else { continue }
            if observers[pid] == nil { observe(pid: pid) }
            let axApp = AXUIElementCreateApplication(pid)
            for el in AX.windows(of: axApp) {
                guard let id = AX.windowID(of: el), AX.isStandardWindow(el), !AX.isMinimized(el),
                      let frame = AX.frame(el), frame.width >= 40, frame.height >= 40 else { continue }
                let title = AX.string(el, kAXTitleAttribute) ?? ""
                let doc = AX.string(el, kAXDocumentAttribute)
                let display = Displays.screen(for: frame).map(Displays.stableID(of:)) ?? ""
                let snap = WindowSnapshot(windowID: id, pid: pid, bundleID: bundle, appName: app.localizedName ?? bundle,
                                          title: title, document: doc, frame: frame, displayID: display)
                if let existing = byID[id] {
                    existing.snapshot = snap
                    found[id] = existing
                } else {
                    found[id] = TrackedWindow(id: id, pid: pid, element: el, snapshot: snap)
                    observers[pid]?.watch(window: el)
                }
            }
        }

        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = found.values.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        byID = found
        windows = sorted
        onChange?()
    }

    /// Re-reads one window's frame and title without a full rescan.
    func refresh(element: AXUIElement) -> CGWindowID? {
        guard let id = AX.windowID(of: element), let w = byID[id] else { return nil }
        if let f = AX.frame(element) {
            if f != w.snapshot.frame { w.previousFrame = w.snapshot.frame }
            w.snapshot.frame = f
            w.snapshot.displayID = Displays.screen(for: f).map(Displays.stableID(of:)) ?? w.snapshot.displayID
        }
        if let t = AX.string(element, kAXTitleAttribute) { w.snapshot.title = t }
        return id
    }

    // MARK: AX observers

    private func observe(pid: pid_t) {
        guard pid != ownPID, observers[pid] == nil else { return }
        if let o = AppObserver(pid: pid, inventory: self) { observers[pid] = o }
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            scheduleRescan()
            if let id = AX.windowID(of: element) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    MainActor.assumeIsolated { self?.onEvent?(.created(id)) }
                }
            }
        case kAXUIElementDestroyedNotification:
            if let id = byID.first(where: { CFEqual($0.value.element, element) })?.key {
                byID[id] = nil
                windows.removeAll { $0.id == id }
                onEvent?(.destroyed(id))
            }
            scheduleRescan()
        case kAXWindowMovedNotification:
            if let id = refresh(element: element) { onEvent?(.moved(id)) }
        case kAXWindowResizedNotification:
            if let id = refresh(element: element) { onEvent?(.resized(id)) }
        case kAXTitleChangedNotification:
            if let id = refresh(element: element) { onEvent?(.titleChanged(id)) }
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if let id = AX.windowID(of: element) { onEvent?(.focused(id)) }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            scheduleRescan()
        default:
            break
        }
    }
}

/// One AXObserver per app process.
@MainActor
private final class AppObserver {
    let pid: pid_t
    let observer: AXObserver
    let app: AXUIElement
    weak var inventory: WindowInventory?
    private var watched: [AXUIElement] = []

    static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
    ]
    static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXTitleChangedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    init?(pid: pid_t, inventory: WindowInventory) {
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let box = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated {
                box.inventory?.handle(notification: name, element: element)
            }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return nil }
        self.pid = pid
        self.observer = obs
        self.app = AXUIElementCreateApplication(pid)
        self.inventory = inventory
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.appNotifications { AXObserverAddNotification(obs, app, n as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        for w in AX.windows(of: app) { watch(window: w) }
    }

    func watch(window: AXUIElement) {
        guard !watched.contains(where: { CFEqual($0, window) }) else { return }
        watched.append(window)
        if watched.count > 64 { watched.removeFirst(watched.count - 64) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications { AXObserverAddNotification(observer, window, n as CFString, refcon) }
    }

    func invalidate() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        watched.removeAll()
    }
}
