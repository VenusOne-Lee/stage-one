import AppKit
import StageOneCore

/// SO-012: park windows of off-stage groups just off-screen (the AeroSpace approach)
/// rather than minimising them, and bring them back to their exact frame.
///
/// Parked frames are written to disk on every change so a crash, a quit or an app
/// relaunch never strands a window off-screen (see SO-131 and `reconcile`).
@MainActor
public final class Parking {
    public struct Record: Codable, Sendable, Equatable {
        public var snapshot: WindowSnapshot
        /// The frame to restore.
        public var frame: CGRect
    }

    public private(set) var records: [CGWindowID: Record] = [:]
    /// SO-015: called when an app put a parked window back on screen (it ignores AX moves).
    /// The window's record is dropped first, so it's treated as never parked.
    public var onIgnoredMove: ((TrackedWindow) -> Void)?
    private let mover: WindowMover
    private let file: URL

    public init(mover: WindowMover = .shared, file: URL = IPC.supportDirectory.appendingPathComponent("parked.json")) {
        self.mover = mover
        self.file = file
        load()
    }

    public func isParked(_ id: CGWindowID) -> Bool { records[id] != nil }

    /// Where parked windows go: 1pt left visible in the bottom-right corner of the desktop.
    public static var parkingOrigin: CGPoint {
        let u = Displays.union
        return CGPoint(x: u.maxX - 1, y: u.maxY - 1)
    }

    /// True when a frame sits in the parking corner.
    public static func looksParked(_ frame: CGRect) -> Bool {
        let p = parkingOrigin
        return frame.minX >= p.x - 4 && frame.minY >= p.y - 40
    }

    public func park(_ window: TrackedWindow) {
        guard records[window.id] == nil else { return }
        let frame = window.liveFrame() ?? window.frame
        records[window.id] = Record(snapshot: window.snapshot, frame: frame)
        save()
        let target = Self.parkingOrigin
        mover.setPosition(window, target)
        // Some apps accept the move and then snap back; look again once they've settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, let window, self.records[window.id] != nil,
                      let now = window.liveFrame(),
                      Uncooperative.ignoredMove(target: target, actual: now) else { return }
                self.records[window.id] = nil
                self.save()
                self.onIgnoredMove?(window)
            }
        }
    }

    /// Restores the exact frame. Returns false if the window wasn't parked.
    @discardableResult
    public func unpark(_ window: TrackedWindow, to frame: CGRect? = nil, animated: Bool = false, delay: TimeInterval = 0) -> Bool {
        guard let rec = records.removeValue(forKey: window.id) else { return false }
        save()
        let target = frame ?? rec.frame
        if animated {
            // Jump to a scaled-down version at the target center first, then grow in (switch motion).
            mover.animate(window, to: target, duration: 0.42, delay: delay)
        } else {
            mover.setFrame(window, target)
        }
        return true
    }

    /// The frame a parked window will come back to.
    public func savedFrame(_ id: CGWindowID) -> CGRect? { records[id]?.frame }

    /// Updates the frame a parked window returns to (used by layouts and reflow).
    public func setSavedFrame(_ id: CGWindowID, _ frame: CGRect) {
        guard records[id] != nil else { return }
        records[id]?.frame = frame
        save()
    }

    /// Re-attaches parked records to live windows after an app relaunch (window ids change)
    /// using identity matching, and rescues any window left in the parking corner that we
    /// have no record of.
    public func reconcile(with inventory: WindowInventory) {
        let live = inventory.windows
        let liveIDs = Set(live.map(\.id))
        let stale = records.filter { !liveIDs.contains($0.key) }
        if !stale.isEmpty {
            let orphans = live.filter { records[$0.id] == nil && Self.looksParked($0.frame) }
            let saved = stale.map { StageScene.Window($0.value.snapshot) }
            let result = IdentityMatcher.match(saved: saved, live: orphans.map(\.snapshot))
            let staleList = Array(stale)
            for m in result.matches {
                let (oldID, rec) = staleList[m.savedIndex]
                records[oldID] = nil
                if let w = inventory[m.windowID] { records[w.id] = Record(snapshot: w.snapshot, frame: rec.frame) }
            }
            // Records for windows that are gone and unmatched: keep for a while (the app may relaunch).
            save()
        }
        for w in live where records[w.id] == nil && Self.looksParked(w.frame) {
            // Unknown window in the corner: bring it back to the middle of the main display.
            if let screen = NSScreen.main {
                let v = Displays.visibleFrame(of: screen)
                let size = CGSize(width: min(w.frame.width, v.width * 0.8), height: min(w.frame.height, v.height * 0.8))
                mover.setFrame(w, CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
    }

    /// Brings every parked window back (Quit, Pause, crash recovery).
    public func unparkAll(in inventory: WindowInventory) {
        for (id, rec) in records {
            if let w = inventory[id] { mover.setFrame(w, rec.frame) }
        }
        records.removeAll()
        save()
    }

    /// Forgets windows that no longer exist and were never matched (after a scene restore).
    public func forget(_ id: CGWindowID) {
        records[id] = nil
        save()
    }

    // MARK: Persistence

    private struct Entry: Codable { var id: CGWindowID; var record: Record }

    private func save() {
        let entries = records.map { Entry(id: $0.key, record: $0.value) }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try IPC.encode(entries).write(to: file, options: .atomic)
        } catch {
            NSLog("Stage One: could not save parked windows: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file), let entries = try? IPC.decode([Entry].self, data) else { return }
        records = Dictionary(entries.map { ($0.id, $0.record) }, uniquingKeysWith: { a, _ in a })
    }
}
