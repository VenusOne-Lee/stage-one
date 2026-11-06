import AppKit
import StageOneCore
import WindowKit

/// SO-070: runs scene rules. Triggers post `RuleEvent`s; a matching, enabled rule shows a
/// 5-second toast with Skip, then restores its scene. The last 50 runs are logged.
@MainActor
final class RuleService: ObservableObject {
    static let shared = RuleService()

    @Published private(set) var log: [RuleRun] = []
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var clock: Timer?
    private var pending: DispatchWorkItem?
    private var installed = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: "ruleLog"),
           let saved = try? JSONDecoder().decode([RuleRun].self, from: data) { log = saved }
    }

    func install() {
        guard !installed else { return }
        installed = true
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append((ws, ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
            let bundle = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { if let bundle { RuleService.shared.post(.appLaunched(bundle)) } }
        }))
        scheduleClock()
    }

    func uninstall() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
        clock?.invalidate()
        clock = nil
        pending?.cancel()
        pending = nil
        installed = false
    }

    /// Fires at the start of every minute for time-of-day rules.
    private func scheduleClock() {
        let now = Date()
        let next = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        let t = Timer(fire: next, interval: 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
                RuleService.shared.post(.time(hour: c.hour ?? 0, minute: c.minute ?? 0))
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    /// Runs the first scene whose rule matches, after a 5-second countdown with Skip.
    func post(_ event: RuleEvent) {
        guard installed, StageController.shared.isRunning, !Preferences.shared.paused else { return }
        let store = SceneStore.shared
        store.reload()
        guard let scene = RuleEngine.scene(for: event, in: store.scenes) else { return }
        let prefs = Preferences.shared
        // Already on stage and unchanged: nothing to do.
        if prefs.currentScene == scene.name && !prefs.sceneEdited { return }
        pending?.cancel()
        let trigger = event.trigger
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                RuleService.shared.pending = nil
                SceneRestore.restore(scene)
                RuleService.shared.record(scene.name, trigger, .ran)
            }
        }
        pending = work
        Toast.shared.show("\(Self.reason(event)). Restoring “\(scene.name)” in 5s…",
                          action: (title: "Skip", run: {
                              work.cancel()
                              RuleService.shared.pending = nil
                              RuleService.shared.record(scene.name, trigger, .skipped)
                          }),
                          duration: RuleEngine.countdown, progress: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + RuleEngine.countdown, execute: work)
    }

    private func record(_ scene: String, _ trigger: RuleTrigger, _ outcome: RuleRun.Outcome) {
        RuleEngine.append(RuleRun(date: Date(), scene: scene, trigger: trigger.rawValue, outcome: outcome), to: &log)
        UserDefaults.standard.set(try? JSONEncoder().encode(log), forKey: "ruleLog")
    }

    static func reason(_ e: RuleEvent) -> String {
        switch e {
        case .displayConnected(let id): return "\(displayName(id)) connected"
        case .displayDisconnected(let id): return "\(displayName(id)) unplugged"
        case .focus(let name): return "\(name) Focus started"
        case .calendar(let title, _): return "“\(title)” is starting"
        case .appLaunched(let b): return "\(appName(b)) opened"
        case .wifi(let n): return "Joined \(n)"
        case .time(let h, let m): return String(format: "It's %02d:%02d", h, m)
        }
    }

    static func displayName(_ id: String) -> String {
        Displays.screen(withID: id)?.localizedName ?? "A display"
    }

    static func appName(_ bundle: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)?.deletingPathExtension().lastPathComponent ?? bundle
    }
}
