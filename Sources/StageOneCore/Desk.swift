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
    public mutating func sync(liveWindowIDs: [UInt32]) {
        let live = Set(liveWindowIDs)
        for i in groups.indices { groups[i].windowIDs.removeAll { !live.contains($0) } }
        let known = Set(groups.flatMap(\.windowIDs))
        let new = liveWindowIDs.filter { !known.contains($0) }
        guard !new.isEmpty else { return }
        if groups.isEmpty { addGroup(named: "Desk") }
        let target = activeIndex ?? 0
        groups[target].windowIDs.insert(contentsOf: new, at: 0)
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
