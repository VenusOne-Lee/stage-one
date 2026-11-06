import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// SO-110: Meeting mode. While it's on, windows of private apps get a frosted cover reading
/// "Hidden while you share", and the strip hides their thumbnails. It turns on by hand
/// (⌃⌥M, the menu, the command bar, Shortcuts), from a scene or rule, or when screen sharing starts.
@MainActor
final class MeetingMode: ObservableObject {
    static let shared = MeetingMode()

    @Published private(set) var on = false
    private var state = MeetingState()
    private var covers: [CGWindowID: PrivacyCover] = [:]
    private var trackTimer: Timer?
    private var shareTimer: Timer?

    func install() {
        SceneOptionsService.setMeetingMode = { MeetingMode.shared.set($0) }
        guard shareTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { MeetingMode.shared.checkSharing() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        shareTimer = t
    }

    func uninstall() {
        shareTimer?.invalidate()
        shareTimer = nil
        apply(false, toast: nil)
        state = MeetingState()
    }

    func toggle() { set(!on) }

    /// By hand, a scene or a rule.
    func set(_ value: Bool) {
        state.set(value)
        apply(value, toast: value ? "Meeting mode on. \(privateSummary) hidden while you share." : "Meeting mode off")
    }

    /// True when this window's preview should be hidden.
    func hides(_ w: TrackedWindow) -> Bool {
        on && Preferences.shared.privateList.isPrivate(bundleID: w.bundleID, title: w.title)
    }

    private var privateSummary: String {
        let names = Preferences.shared.privateList.apps.compactMap(MeetingMode.appName)
        switch names.count {
        case 0: return "Private windows are"
        case 1: return "\(names[0]) is"
        case 2: return "\(names[0]) and \(names[1]) are"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more are"
        }
    }

    static func appName(_ bundle: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)?.deletingPathExtension().lastPathComponent
    }

    private func apply(_ value: Bool, toast: String?) {
        let changed = on != value
        on = value
        SceneOptionsService.meetingModeOn = value
        if value {
            refresh()
            if trackTimer == nil {
                // Follow private windows as they move, and keep the cover just above them.
                let t = Timer(timeInterval: 0.25, repeats: true) { _ in
                    MainActor.assumeIsolated { MeetingMode.shared.refresh() }
                }
                t.tolerance = 0.05
                RunLoop.main.add(t, forMode: .common)
                trackTimer = t
            }
        } else {
            trackTimer?.invalidate()
            trackTimer = nil
            covers.values.forEach { $0.orderOut(nil) }
            covers.removeAll()
        }
        if changed, let toast { Toast.shared.show(toast, duration: 3) }
        StageController.shared.objectWillChange.send()
    }

    private func checkSharing() {
        guard Preferences.shared.meetingAuto else { return }
        guard let v = state.sharing(Self.screenIsShared(), autoEnabled: true) else { return }
        apply(v, toast: v ? "You're sharing your screen. Meeting mode is on." : "Sharing stopped. Meeting mode is off.")
    }

    /// Puts a cover over every private window that's on screen.
    private func refresh() {
        let c = StageController.shared
        let list = Preferences.shared.privateList
        var keep = Set<CGWindowID>()
        for w in c.inventory.windows where !c.parking.isParked(w.id) && list.isPrivate(bundleID: w.bundleID, title: w.title) {
            guard let frame = w.liveFrame(), frame.width > 40, frame.height > 40 else { continue }
            keep.insert(w.id)
            let cover = covers[w.id] ?? PrivacyCover(appName: w.app?.localizedName ?? "This app")
            covers[w.id] = cover
            cover.cover(frame: frame, windowID: w.id)
        }
        for (id, cover) in covers where !keep.contains(id) {
            cover.orderOut(nil)
            covers[id] = nil
        }
    }

    /// macOS Screen Sharing sets a session flag; meeting apps show a sharing bar or banner.
    static func screenIsShared() -> Bool {
        let session = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsShared"] as? Bool ?? false
        if session { return true }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = info.map {
            SharingDetector.Window(owner: $0[kCGWindowOwnerName as String] as? String ?? "",
                                   title: $0[kCGWindowName as String] as? String ?? "")
        }
        return SharingDetector.isSharing(sessionShared: false, windows: windows)
    }
}

/// The frosted panel laid over a private window. Clicks pass through to the window.
@MainActor
final class PrivacyCover: NSPanel {
    init(appName: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .normal
        collectionBehavior = [.managed, .ignoresCycle, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .aqua)
        let view = PrivacyCoverView(appName: appName).environment(\.colorScheme, .light)
        contentView = NSHostingView(rootView: view)
    }

    /// `frame` is in Accessibility (top-left) coordinates.
    func cover(frame: CGRect, windowID: CGWindowID) {
        let target = CoordinateSpace.flip(frame, primaryHeight: Displays.primaryHeight)
        if self.frame != target { setFrame(target, display: true) }
        order(.above, relativeTo: Int(windowID))
    }
}

private struct PrivacyCoverView: View {
    let appName: String

    var body: some View {
        ZStack {
            VisualEffect()
            Color(hex: 0xfffdfb, alpha: 0.72)
            VStack(spacing: 4) {
                Text("Hidden while you share").font(Theme.display(17)).foregroundStyle(Theme.ink)
                Text("\(appName) is private in Meeting mode").font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
