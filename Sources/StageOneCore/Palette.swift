import Foundation

/// SO-080: one row of the ⌘K command bar.
public struct PaletteItem: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case group = "Group", scene = "Scene", arrange = "Arrange", time = "Time", rules = "Rules", share = "Share", window = "Window"
    }

    public enum Action: Sendable, Equatable {
        case switchGroup(UUID)
        case restoreScene(String)
        case saveScene
        case arrange(LayoutKind)
        case openRewind
        case rewind(Date)
        case openRules
        case focusWindow(UInt32)
        case toggleMeetingMode
    }

    public var kind: Kind
    public var title: String
    /// Right-hand text: a shortcut (⌥1, ⌘⇧S) or, for windows, the group they're in.
    public var hint: String
    public var action: Action

    public init(_ kind: Kind, _ title: String, hint: String = "", action: Action) {
        self.kind = kind
        self.title = title
        self.hint = hint
        self.action = action
    }
}

/// SO-080: filtering and keyboard selection for the command bar. Pure, so it is tested.
public enum Palette {
    /// Rows shown at once, as in the prototype.
    public static let limit = 12

    /// Items for `query`, best first. An empty query keeps the given order.
    /// Titles are matched first; the type and hint ("window", a group name) also match, a
    /// little lower, so "window mail" or "⌥2" find what you'd expect.
    public static func filter(_ items: [PaletteItem], query: String, limit: Int = Palette.limit) -> [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(items.prefix(limit)) }
        let scored: [(offset: Int, item: PaletteItem, score: Double)] = items.enumerated().compactMap { i, item in
            let onTitle = Fuzzy.score(q, in: item.title)
            let onAll = Fuzzy.score(q, in: "\(item.kind.rawValue) \(item.title) \(item.hint)").map { $0 - 3 }
            guard let s = [onTitle, onAll].compactMap({ $0 }).max() else { return nil }
            return (i, item, s)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .prefix(limit).map(\.item)
    }

    /// Moves the highlighted row by `delta`, staying within `count` rows.
    public static func move(_ selection: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(selection + delta, 0), count - 1)
    }

    /// "Rewind to 14:30" or "Rewind to Tue 09:15" for older points.
    public static func rewindTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return "Rewind to \(f.string(from: date))"
    }
}
