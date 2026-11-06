import AppKit
import StageOneCore
import WindowKit

/// SO-060: automatic snapshots of the desk, every 15 minutes and on sleep, display
/// change and quit. Identical states are skipped; snapshots are kept 7 days and the
/// folder stays under 20 MB. Each snapshot is a compact `.stagescene` file.
@MainActor
final class RewindStore: ObservableObject {
    static let shared = RewindStore()

    struct Snapshot: Identifiable, Equatable {
        var date: Date
        var url: URL
        var id: URL { url }
    }

    @Published private(set) var snapshots: [Snapshot] = []
    private var timer: Timer?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var latestFingerprint: String?
    private var displayWork: DispatchWorkItem?

    static var directory: URL { IPC.supportDirectory.appendingPathComponent("Snapshots", isDirectory: true) }

    func install() {
        guard timer == nil else { return }
        reload()
        latestFingerprint = snapshots.last.flatMap { load($0)?.fingerprint() }
        let t = Timer(timeInterval: RewindPolicy.interval, repeats: true) { _ in
            MainActor.assumeIsolated { RewindStore.shared.take() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let ws = NSWorkspace.shared.notificationCenter
        tokens.append((ws, ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RewindStore.shared.take() }
        }))
        let nc = NotificationCenter.default
        tokens.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            // Snapshot the desk as it was, before windows settle on the new displays.
            MainActor.assumeIsolated { RewindStore.shared.displaysChanged() }
        }))
        CommandRouter.rewind = { command in
            guard case .rewind(let date) = command else { return .fail("Not a rewind command.") }
            return RewindStore.shared.rewind(to: date)
        }
        take()
    }

    /// Takes a last snapshot (quit or pause) and stops.
    func uninstall() {
        take()
        timer?.invalidate()
        timer = nil
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
    }

    private func displaysChanged() {
        guard displayWork == nil else { return }
        take()
        let work = DispatchWorkItem { MainActor.assumeIsolated { RewindStore.shared.displayWork = nil } }
        displayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Saves a snapshot unless the desk is the same as the latest one.
    func take(now: Date = Date()) {
        let c = StageController.shared
        guard c.isRunning, !c.inventory.windows.isEmpty else { return }
        let scene = Scenes.capture(name: "Snapshot")
        let fp = scene.fingerprint()
        guard RewindPolicy.shouldSave(fp, latest: latestFingerprint) else { return }
        var named = scene
        named.name = now.formatted(date: .abbreviated, time: .shortened)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            let url = Self.directory.appendingPathComponent(RewindPolicy.fileName(for: now))
            try e.encode(named).write(to: url, options: .atomic)
            latestFingerprint = fp
        } catch {
            NSLog("Stage One: snapshot failed: \(error)")
        }
        prune(now: now)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        snapshots = urls.compactMap { url in
            RewindPolicy.date(fromFileName: url.lastPathComponent).map { Snapshot(date: $0, url: url) }
        }.sorted { $0.date < $1.date }
    }

    func load(_ s: Snapshot) -> StageScene? {
        guard let data = try? Data(contentsOf: s.url) else { return nil }
        return try? StageScene.decode(data)
    }

    private func prune(now: Date) {
        reload()
        let entries = snapshots.map { s in
            RewindPolicy.Entry(date: s.date, bytes: (try? s.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        for i in RewindPolicy.prune(entries, now: now) { try? FileManager.default.removeItem(at: snapshots[i].url) }
    }

    /// `stage rewind [--to time]` and stageone://rewind.
    func rewind(to date: Date?) -> CommandReply {
        reload()
        guard let i = RewindPolicy.target(for: date, in: snapshots.map(\.date), now: Date()),
              let scene = load(snapshots[i]) else {
            return .fail("No snapshot that far back. Snapshots are kept for 7 days.")
        }
        go(to: scene, at: snapshots[i].date)
        return CommandReply(ok: true, message: "Rewound to \(snapshots[i].date.formatted(date: .abbreviated, time: .shortened)).")
    }

    /// Restores a snapshot like a scene (with Undo), without making it the current scene.
    func go(to scene: StageScene, at date: Date) {
        SceneRestore.restore(scene, undoable: true, relaunch: true, quiet: true, setsCurrent: false)
        Toast.shared.show("Back to \(date.formatted(date: .omitted, time: .shortened))",
                          detail: date.formatted(.relative(presentation: .named)),
                          action: (title: "Undo", run: { SceneRestore.undo() }), duration: 30)
    }
}
