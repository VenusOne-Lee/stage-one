import AppKit
import StageOneCore
import WindowKit

/// The hub: owns the desk (groups), the window engine and the strip, and performs
/// every desk change. UI and commands call into this; nothing else moves windows.
@MainActor
final class StageController: ObservableObject {
    static let shared = StageController()

    let inventory = WindowInventory()
    let parking = Parking()
    let mover = WindowMover.shared
    let thumbnails = Thumbnails()
    let prefs = Preferences.shared

    @Published private(set) var desk = Desk()
    /// Bumped whenever window data the strip shows changes.
    @Published private(set) var revision = 0
    /// Last-known frames of on-stage windows; used to tell drags from programmatic moves.
    private var switching = false
    private var thumbTimer: Timer?
    private var started = false
    /// Hooks other features register (lane guard, edited flag, rewind, rules...).
    var onWindowEvent: [(WindowEvent) -> Void] = []
    var onDeskChange: [() -> Void] = []

    /// SO-014: per-Space groups. The desks of Spaces not showing, and the Space `desk` belongs to.
    private var spaceDesks = SpaceDesks()
    private var spaceKey: String?

    private init() {
        if let data = prefs.savedDesk, let saved = try? IPC.decode(Desk.self, data) { desk = saved }
        if let data = prefs.savedSpaceDesks, let saved = try? IPC.decode(SpaceDesks.self, data) { spaceDesks = saved }
        spaceKey = prefs.savedSpaceKey
    }

    // MARK: Lifecycle

    func start() {
        guard !started, Permissions.accessibility else { return }
        started = true
        inventory.onChange = { [weak self] in self?.inventoryChanged() }
        inventory.onEvent = { [weak self] e in self?.handle(e) }
        inventory.floatingBundleIDs = Uncooperative.floating(prefs.appExceptions)
        inventory.start()
        parking.reconcile(with: inventory)
        let stale = desk.groups.isEmpty || desk.groups.allSatisfy({ $0.windowIDs.allSatisfy { !inventory.aliveIDs.contains($0) } })
        if stale {
            desk = Desk()
            importWindowsByApp()
            // After a restart window ids are new: bring back the last session by identity.
            if let last = SessionAutosave.lastSession(), !inventory.windows.isEmpty {
                SceneRestore.restore(last, undoable: false, relaunch: false, quiet: true)
                Preferences.shared.currentScene = nil
            }
        }
        inventoryChanged()
        enforceStage()
        thumbTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureOnStage() }
        }
        thumbTimer?.tolerance = 0.5
        captureAll()
        Features.start()
    }

    /// Puts every window back where the user can see it (Quit and Pause).
    func stop() {
        Features.stop()
        thumbTimer?.invalidate()
        parking.unparkAll(in: inventory)
        inventory.stop()
        started = false
    }

    var isRunning: Bool { started }

    // MARK: Desk changes

    func mutateDesk(_ change: (inout Desk) -> Void) {
        change(&desk)
        deskChanged()
    }

    private func deskChanged() {
        if let data = try? IPC.encode(desk) { prefs.savedDesk = data }
        if prefs.spacesMode == .perSpace {
            if let data = try? IPC.encode(spaceDesks) { prefs.savedSpaceDesks = data }
            prefs.savedSpaceKey = spaceKey
        }
        revision &+= 1
        onDeskChange.forEach { $0() }
    }

    private func inventoryChanged() {
        let perSpace = prefs.spacesMode == .perSpace && Spaces.isAvailable
        let newSpace = perSpace && followSpace()
        var ids = inventory.windows.map(\.id)
        if perSpace, let key = spaceKey, let sid = UInt64(key) {
            // AX can list windows from other Spaces; only this Space's windows join its desk.
            ids = ids.filter { Spaces.spaces(of: $0)?.contains(sid) ?? true }
            spaceDesks.release(Set(ids))
            spaceDesks.prune(alive: inventory.aliveIDs)
        }
        // Full screen windows join a group too, so the strip can show them (with a badge).
        let full = inventory.fullscreen.keys.filter { !(perSpace && spaceDesks.contains($0)) }
        let before = desk
        desk.sync(liveWindowIDs: ids + full, aliveIDs: inventory.aliveIDs)
        // A window that opens while its group is off stage stays where it is (parked groups only gain
        // windows by drag or restore); sync puts new windows on stage.
        if newSpace && before.groups.isEmpty {
            importWindowsByApp(only: Set(ids))
        } else if desk != before || newSpace {
            deskChanged()
            if newSpace { enforceStage() }
        } else {
            revision &+= 1
        }
    }

    // MARK: Spaces (SO-014)

    /// Per-Space mode: when another Space shows, store this desk and bring out that Space's.
    /// Full screen Spaces keep the desk that was showing. Returns true if the Space changed.
    private func followSpace() -> Bool {
        guard let sid = Spaces.active(), !Spaces.isFullscreen(sid) else { return false }
        let key = String(sid)
        guard key != spaceKey else { return false }
        guard spaceKey != nil else { spaceKey = key; return false }  // the desk already is this Space's
        desk = spaceDesks.switchSpace(current: desk, from: spaceKey, to: key)
        spaceKey = key
        return true
    }

    /// Settings changed between one set of groups and one per Space.
    func spacesModeChanged() {
        guard started else { return }
        if prefs.spacesMode == .perSpace {
            guard let sid = Spaces.active() else { return }
            spaceDesks = SpaceDesks()
            spaceKey = String(sid)
            desk = spaceDesks.split(desk, current: String(sid)) { id in
                // A window's Space, ignoring full screen ones (those stay with this desk).
                guard let spaces = Spaces.spaces(of: id), !spaces.contains(sid),
                      let other = spaces.first(where: { !Spaces.isFullscreen($0) }) else { return nil }
                return String(other)
            }
        } else {
            desk = spaceDesks.merge(into: desk)
            spaceKey = nil
            prefs.savedSpaceDesks = nil
            prefs.savedSpaceKey = nil
        }
        deskChanged()
        enforceStage()
    }

    /// True when a group holds a window in native full screen.
    func hasFullscreen(_ group: StageGroup) -> Bool {
        group.windowIDs.contains { inventory.isFullscreen($0) }
    }

    /// SO-003: one group per app, at most 8; extra apps join the last group.
    func importWindowsByApp(maxGroups: Int = 8, only: Set<CGWindowID>? = nil) {
        var order: [String] = []
        var byApp: [String: [CGWindowID]] = [:]
        var names: [String: String] = [:]
        for w in inventory.windows where only?.contains(w.id) ?? true {
            if byApp[w.bundleID] == nil { order.append(w.bundleID) }
            byApp[w.bundleID, default: []].append(w.id)
            names[w.bundleID] = w.snapshot.appName
        }
        var d = Desk()
        for (i, b) in order.enumerated() {
            if i < maxGroups {
                d.addGroup(named: names[b] ?? b, windowIDs: byApp[b] ?? [])
            } else if let last = d.groups.indices.last {
                d.groups[last].windowIDs += byApp[b] ?? []
                d.groups[last].name = "More"
            }
        }
        if d.groups.isEmpty { d.addGroup(named: "Desk") }
        // The front-most window's group goes on stage.
        if let front = inventory.windows.first(where: { only?.contains($0.id) ?? true }),
           let g = d.group(containing: front.id) { d.activeID = g.id }
        desk = d
        deskChanged()
        enforceStage()
    }

    /// "Start fresh": everything in one group.
    func importAsOneGroup() {
        var d = Desk()
        d.addGroup(named: "Desk", windowIDs: inventory.windows.map(\.id))
        desk = d
        deskChanged()
        enforceStage()
    }

    /// Makes reality match the desk: active group's windows unparked, all others parked.
    func enforceStage() {
        guard started else { return }
        let activeIDs = Set(desk.active?.windowIDs ?? [])
        let grouped = Set(desk.groups.flatMap(\.windowIDs))
        // Windows outside this desk (another Space's, in per-Space mode) are left alone.
        for w in inventory.windows where grouped.contains(w.id) {
            if activeIDs.contains(w.id) {
                if parking.isParked(w.id) { parking.unpark(w) }
            } else if !parking.isParked(w.id) {
                capture([w.id])
                parking.park(w)
            }
        }
    }

    // MARK: Switching (SO-020)

    /// Swaps a group onto the stage with the switch motion.
    func switchTo(_ groupID: UUID, animated: Bool = true) {
        guard started, groupID != desk.activeID, let target = desk.groups.first(where: { $0.id == groupID }) else {
            raiseActive()
            return
        }
        switching = true
        let outgoing = (desk.active?.windowIDs ?? []).compactMap { inventory[$0] }
        capture(outgoing.map(\.id))
        for w in outgoing { parking.park(w) }
        desk.activeID = groupID
        deskChanged()

        let incoming = target.windowIDs.compactMap { inventory[$0] }
        let motion = animated && !mover.reduceMotion && incoming.count <= 12
        for (i, w) in incoming.enumerated().reversed() {
            guard let saved = parking.savedFrame(w.id) else { continue }
            let final = desk.active.map { applyLayoutFrame(for: w.id, in: $0) ?? saved } ?? saved
            if motion {
                // Scale in from 0.55 around the final centre, 45ms stagger.
                let s: CGFloat = 0.55
                let start = CGRect(x: final.midX - final.width * s / 2, y: final.midY - final.height * s / 2,
                                   width: final.width * s, height: final.height * s)
                parking.unpark(w, to: start)
                mover.animate(w, to: final, duration: 0.42, delay: Double(i) * 0.045)
            } else {
                parking.unpark(w, to: final)
            }
        }
        raiseActive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { self?.switching = false }
        }
    }

    /// SO-025: add a group's windows to the current stage instead of swapping.
    func addToStage(_ groupID: UUID) {
        guard let activeID = desk.activeID, groupID != activeID,
              let g = desk.groups.first(where: { $0.id == groupID }) else { return }
        for id in g.windowIDs {
            if let w = inventory[id] { parking.unpark(w) }
        }
        mutateDesk { d in
            for id in g.windowIDs.reversed() { d.move(windowID: id, to: activeID) }
            d.remove(groupID, mergingInto: activeID)
        }
        raiseActive()
    }

    func switchTo(index: Int) {
        guard desk.groups.indices.contains(index) else { return }
        switchTo(desk.groups[index].id)
    }

    /// Brings the on-stage windows to the front, front window last, and activates its app.
    func raiseActive() {
        let ws = (desk.active?.windowIDs ?? []).compactMap { inventory[$0] }
        // A group that only holds a full screen window: show it, which moves to its Space.
        if ws.isEmpty, let f = (desk.active?.windowIDs ?? []).compactMap({ inventory.fullscreen[$0] }).first {
            AX.raise(f.element)
            f.app?.activate()
            return
        }
        for w in ws.reversed() { AX.raise(w.element) }
        ws.first?.app?.activate()
    }

    /// Hook for layouts (SO-040): the frame a window should take in its group's layout.
    var layoutFrame: ((CGWindowID, StageGroup) -> CGRect?)?
    private func applyLayoutFrame(for id: CGWindowID, in group: StageGroup) -> CGRect? { layoutFrame?(id, group) }

    // MARK: Group editing (SO-022, SO-023)

    func move(window id: CGWindowID, to groupID: UUID) {
        guard desk.group(containing: id)?.id != groupID else { return }
        mutateDesk { $0.move(windowID: id, to: groupID) }
        guard let w = inventory[id] else { return }
        if groupID != desk.activeID {
            capture([id])
            parking.park(w)
        } else if parking.isParked(id) {
            parking.unpark(w)
            AX.raise(w.element)
        }
    }

    @discardableResult
    func newGroup(with id: CGWindowID?) -> UUID {
        let name = id.flatMap { inventory[$0]?.snapshot.appName } ?? "New group"
        var gid = UUID()
        mutateDesk { d in
            let g = d.addGroup(named: name, windowIDs: id.map { [$0] } ?? [])
            gid = g.id
        }
        if let id, let w = inventory[id] { capture([id]); parking.park(w) }
        return gid
    }

    func rename(_ groupID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateDesk { $0.rename(groupID, to: trimmed) }
    }

    func setColor(_ groupID: UUID, _ hex: String) {
        mutateDesk { d in if let i = d.groups.firstIndex(where: { $0.id == groupID }) { d.groups[i].color = hex } }
    }

    /// Close group: its windows join the stage (nothing is closed).
    func closeGroup(_ groupID: UUID) {
        guard let g = desk.groups.first(where: { $0.id == groupID }) else { return }
        if groupID == desk.activeID, desk.groups.count > 1 {
            mutateDesk { $0.remove(groupID, mergingInto: nil) }
            enforceStage()
            return
        }
        for id in g.windowIDs { if let w = inventory[id] { parking.unpark(w) } }
        mutateDesk { $0.remove(groupID, mergingInto: $0.activeID) }
    }

    func reorder(from: Int, to: Int) { mutateDesk { $0.reorder(from: from, to: to) } }

    /// Assigns a group to a display; its windows are reflowed there when it next comes on stage.
    func moveGroup(_ groupID: UUID, toDisplay displayID: String) {
        guard let g = desk.groups.first(where: { $0.id == groupID }),
              let screen = Displays.screen(withID: displayID),
              let target = ScreenLayouts.current(for: screen) else { return }
        for id in g.windowIDs {
            guard let w = inventory[id] else { continue }
            let current = parking.savedFrame(id) ?? w.frame
            let source = ScreenLayouts.layout(containing: current)?.usableFrame ?? target.usableFrame
            let moved = Reflow.remap(current, from: source, to: target.usableFrame)
            if parking.isParked(id) { parking.setSavedFrame(id, moved) } else { mover.setFrame(w, moved) }
        }
        mutateDesk { d in if let i = d.groups.firstIndex(where: { $0.id == groupID }) { d.groups[i].displayID = displayID } }
    }

    // MARK: Events

    private func handle(_ e: WindowEvent) {
        switch e {
        case .focused(let id):
            // Clicking a parked app's Dock icon or ⌘-tabbing to it brings its group on stage.
            if !switching, let g = desk.group(containing: id), g.id != desk.activeID, parking.isParked(id) {
                switchTo(g.id)
            }
        case .appTerminated:
            parking.reconcile(with: inventory)
        case .appLaunched:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.parking.reconcile(with: self.inventory)
                }
            }
        default:
            break
        }
        onWindowEvent.forEach { $0(e) }
    }

    /// True while a group switch is animating; the lane guard ignores moves then.
    var isSwitching: Bool { switching || mover.isAnimating }

    // MARK: Thumbnails

    private func capture(_ ids: [CGWindowID]) {
        guard prefs.livePreviews else { return }
        thumbnails.capture(ids)
    }

    private func captureOnStage() {
        guard started, !prefs.paused else { return }  // SO-130: no refresh while paused
        capture(desk.active?.windowIDs ?? [])
    }

    func captureAll() { capture(inventory.windows.map(\.id)) }

    // MARK: Lookups for UI

    /// Windows to preview for a group, full screen ones included (they're never moved).
    func windows(of group: StageGroup) -> [TrackedWindow] {
        group.windowIDs.compactMap { inventory[$0] ?? inventory.fullscreen[$0] }
    }

    /// App names in a group, for the strip's search (SO-024).
    func appNames(of group: StageGroup) -> [String] {
        Array(Set(windows(of: group).map(\.snapshot.appName)))
    }

    func appIcons(of group: StageGroup, limit: Int = 2) -> [NSImage] {
        var seen = Set<pid_t>(), icons: [NSImage] = []
        for w in windows(of: group) where !seen.contains(w.pid) {
            seen.insert(w.pid)
            if let icon = w.app?.icon { icons.append(icon) }
            if icons.count == limit { break }
        }
        return icons
    }
}
