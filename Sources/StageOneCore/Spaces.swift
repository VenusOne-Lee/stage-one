import Foundation

/// SO-014: whether every macOS Space has its own groups, or all Spaces share one set.
public enum SpacesMode: String, Codable, Sendable, CaseIterable {
    /// One set of groups across every Space (default).
    case shared
    /// Each Space keeps its own groups and its own group on stage.
    case perSpace
}

/// The desks of Spaces that aren't showing, keyed by Space id. The showing Space's desk
/// lives in the controller; this holds the rest.
public struct SpaceDesks: Codable, Sendable, Equatable {
    public var desks: [String: Desk]

    public init(desks: [String: Desk] = [:]) { self.desks = desks }

    /// Stores `current` as the desk of `from` and hands back the desk of `to`.
    /// A Space seen for the first time gets an empty desk (the caller fills it).
    public mutating func switchSpace(current: Desk, from: String?, to: String) -> Desk {
        if let from, from != to { desks[from] = current }
        return desks.removeValue(forKey: to) ?? Desk()
    }

    /// True when a window belongs to one of the stored (not showing) Spaces.
    public func contains(_ windowID: UInt32) -> Bool {
        desks.values.contains { $0.group(containing: windowID) != nil }
    }

    /// Windows that now show on another Space leave the desks they were in.
    public mutating func release(_ windowIDs: Set<UInt32>) {
        guard !windowIDs.isEmpty else { return }
        for key in desks.keys {
            for i in desks[key]!.groups.indices {
                desks[key]!.groups[i].windowIDs.removeAll { windowIDs.contains($0) }
            }
        }
    }

    /// Drops closed windows, and Spaces whose groups are all empty.
    public mutating func prune(alive: Set<UInt32>) {
        for key in desks.keys {
            for i in desks[key]!.groups.indices {
                desks[key]!.groups[i].windowIDs.removeAll { !alive.contains($0) }
            }
            if desks[key]!.groups.allSatisfy({ $0.windowIDs.isEmpty }) { desks[key] = nil }
        }
    }

    /// Turning per-Space groups on: windows that live on another Space move to that Space's
    /// desk, keeping their group's name and colour. Returns what stays on the `current` Space.
    /// `spaceOf` returns nil for windows whose Space is unknown; those stay put.
    public mutating func split(_ desk: Desk, current: String, spaceOf: (UInt32) -> String?) -> Desk {
        var here = desk
        for (gi, g) in desk.groups.enumerated() {
            for id in g.windowIDs {
                guard let space = spaceOf(id), space != current else { continue }
                here.groups[gi].windowIDs.removeAll { $0 == id }
                var d = desks[space] ?? Desk()
                if let j = d.groups.firstIndex(where: { $0.id == g.id }) {
                    d.groups[j].windowIDs.append(id)
                } else {
                    var copy = g
                    copy.windowIDs = [id]
                    d.groups.append(copy)
                }
                if d.activeID == nil || g.id == desk.activeID { d.activeID = g.id }
                desks[space] = d
            }
        }
        // Groups left empty here only existed on other Spaces.
        let emptied = Set(desk.groups.filter { !$0.windowIDs.isEmpty }.map(\.id))
        here.groups.removeAll { $0.windowIDs.isEmpty && emptied.contains($0.id) }
        if here.active == nil { here.activeID = here.groups.first?.id }
        return here
    }

    /// Switching to one shared set: the other Spaces' groups are appended to `current`,
    /// skipping empty ones and windows already grouped.
    public mutating func merge(into current: Desk) -> Desk {
        var d = current
        var known = Set(d.groups.flatMap(\.windowIDs))
        for key in desks.keys.sorted() {
            for var g in desks[key]!.groups {
                g.windowIDs.removeAll { known.contains($0) }
                guard !g.windowIDs.isEmpty else { continue }
                known.formUnion(g.windowIDs)
                d.groups.append(g)
            }
        }
        desks = [:]
        if d.activeID == nil { d.activeID = d.groups.first?.id }
        return d
    }
}
