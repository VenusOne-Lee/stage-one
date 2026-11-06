import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A window as the core sees it: everything needed to save, match and place it.
public struct WindowSnapshot: Codable, Sendable, Equatable {
    /// Runtime id (CGWindowID). Not stable across launches; never matched on its own.
    public var windowID: UInt32
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    public var document: String?
    public var frame: CGRect
    public var displayID: String

    public init(windowID: UInt32, pid: Int32, bundleID: String, appName: String, title: String,
                document: String? = nil, frame: CGRect, displayID: String) {
        self.windowID = windowID
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.document = document
        self.frame = frame
        self.displayID = displayID
    }
}

/// The group palette. Orange first; deliberately no greens.
public enum GroupColor {
    public static let palette = ["#ef6f2e", "#3b63e0", "#f2b33d", "#e0503d", "#8a5cd6", "#d6457f", "#2f8fd8", "#b9bcc7"]
    public static func next(after used: [String]) -> String {
        palette.first { !used.contains($0) } ?? palette[used.count % palette.count]
    }
}

public struct StageGroup: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var color: String
    public var layout: LayoutKind
    public var displayID: String?
    /// Window ids in stacking order, front first.
    public var windowIDs: [UInt32]

    public init(id: UUID = UUID(), name: String, color: String = GroupColor.palette[0],
                layout: LayoutKind = .free, displayID: String? = nil, windowIDs: [UInt32] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.layout = layout
        self.displayID = displayID
        self.windowIDs = windowIDs
    }
}

/// Groups plus which one is on stage. Pure value type; the app owns one and mutates it.
public struct Desk: Codable, Sendable, Equatable {
    public var groups: [StageGroup]
    public var activeID: UUID?

    public init(groups: [StageGroup] = [], activeID: UUID? = nil) {
        self.groups = groups
        self.activeID = activeID ?? groups.first?.id
    }

    public var active: StageGroup? { groups.first { $0.id == activeID } }
    public var activeIndex: Int? { groups.firstIndex { $0.id == activeID } }
    /// Groups shown in the strip: everything except the one on stage.
    public var stripGroups: [StageGroup] { groups.filter { $0.id != activeID } }

    public func group(containing windowID: UInt32) -> StageGroup? {
        groups.first { $0.windowIDs.contains(windowID) }
    }

    public func group(named query: String) -> StageGroup? {
        if let n = Int(query), n >= 1, n <= groups.count { return groups[n - 1] }
        let q = query.lowercased()
        return groups.first { $0.name.lowercased() == q } ?? groups.first { $0.name.lowercased().hasPrefix(q) }
    }

    @discardableResult
    public mutating func addGroup(named name: String, windowIDs: [UInt32] = []) -> StageGroup {
        for i in groups.indices { groups[i].windowIDs.removeAll { windowIDs.contains($0) } }
        let g = StageGroup(name: name, color: GroupColor.next(after: groups.map(\.color)), windowIDs: windowIDs)
        groups.append(g)
        if activeID == nil { activeID = g.id }
        return g
    }

    /// Moves a window into a group (removing it from any other group).
    public mutating func move(windowID: UInt32, to groupID: UUID) {
        for i in groups.indices { groups[i].windowIDs.removeAll { $0 == windowID } }
        if let i = groups.firstIndex(where: { $0.id == groupID }) { groups[i].windowIDs.insert(windowID, at: 0) }
    }

    /// Adds unknown windows to the active group (new windows open on stage) and drops closed ones.
    /// `aliveIDs` (SO-014) are windows that still exist but can't be managed right now, such as
    /// windows on another Space or in native full screen: they keep their group.
    public mutating func sync(liveWindowIDs: [UInt32], aliveIDs: Set<UInt32> = []) {
        sync(liveWindowIDs: liveWindowIDs, aliveIDs: aliveIDs, apps: [:])
    }

    /// Drops closed windows and places new ones, the way Stage Manager does:
    /// - A group whose last window closed goes away (the active one stays, so the stage has a home).
    /// - A new window joins the stage when the stage already shows its app, or when it comes
    ///   from a background app (nothing jumps away from what the user is doing).
    /// - A new window from the app the user is in (`frontApp`) joins the group that already holds
    ///   that app, or a new group named after it (`names`). That group's id is returned: the caller
    ///   switches to it, so opening an app gives it its own stage instead of piling onto this one.
    /// Without `apps` every new window joins the stage.
    @discardableResult
    public mutating func sync(liveWindowIDs: [UInt32], aliveIDs: Set<UInt32> = [], apps: [UInt32: String],
                              names: [String: String] = [:], frontApp: String? = nil) -> UUID? {
        let live = Set(liveWindowIDs).union(aliveIDs)
        var emptied = Set<UUID>()
        for i in groups.indices {
            let before = groups[i].windowIDs.count
            groups[i].windowIDs.removeAll { !live.contains($0) }
            if before > 0, groups[i].windowIDs.isEmpty { emptied.insert(groups[i].id) }
        }
        groups.removeAll { emptied.contains($0.id) && $0.id != activeID }

        let known = Set(groups.flatMap(\.windowIDs))
        let new = liveWindowIDs.filter { !known.contains($0) }
        guard !new.isEmpty else { return nil }
        if groups.isEmpty { addGroup(named: "Desk") }
        let target = activeIndex ?? 0
        var onStage = Set(groups[target].windowIDs.compactMap { apps[$0] })
        var toStage: [UInt32] = []
        var activate: UUID?
        for id in new {
            guard let app = apps[id], app == frontApp, !onStage.contains(app) else {
                toStage.append(id)
                continue
            }
            if let i = groups.firstIndex(where: { g in g.windowIDs.contains { apps[$0] == app } }) {
                groups[i].windowIDs.insert(id, at: 0)
                activate = groups[i].id
            } else if groups[target].windowIDs.isEmpty {
                // An empty stage simply takes the app, and its name when its last window just closed.
                groups[target].windowIDs.insert(id, at: 0)
                if emptied.contains(groups[target].id) { groups[target].name = names[app] ?? groups[target].name }
                onStage.insert(app)
            } else {
                activate = addGroup(named: names[app] ?? app, windowIDs: [id]).id
            }
        }
        groups[target].windowIDs.insert(contentsOf: toStage, at: 0)
        return activate == activeID ? nil : activate
    }

    /// Removes groups with no windows, except the one on stage. Used at launch, where an empty
    /// group left from the last session has nothing to show.
    public mutating func dropEmptyGroups() {
        groups.removeAll { $0.windowIDs.isEmpty && $0.id != activeID }
    }

    public mutating func rename(_ id: UUID, to name: String) {
        if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].name = name }
    }

    public mutating func remove(_ id: UUID, mergingInto target: UUID? = nil) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let ws = groups[i].windowIDs
        groups.remove(at: i)
        let destination = target ?? activeID ?? groups.first?.id
        if let d = destination, let j = groups.firstIndex(where: { $0.id == d }) { groups[j].windowIDs += ws }
        if activeID == id { activeID = groups.first?.id }
    }

    public mutating func reorder(from: Int, to: Int) {
        guard groups.indices.contains(from) else { return }
        let g = groups.remove(at: from)
        groups.insert(g, at: max(0, min(to, groups.count)))
    }
}
