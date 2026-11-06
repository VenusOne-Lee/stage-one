import Foundation

/// SO-110 / SO-111: apps and windows that Meeting mode hides while you share your screen.
public struct PrivateList: Codable, Sendable, Equatable {
    /// A single window, by a title pattern. `*` matches anything; without `*` the title only has
    /// to contain the pattern. Case is ignored. `bundleID` nil means any app.
    public struct TitleRule: Codable, Sendable, Equatable, Hashable {
        public var bundleID: String?
        public var pattern: String

        public init(bundleID: String? = nil, pattern: String) {
            self.bundleID = bundleID; self.pattern = pattern
        }

        public func matches(bundleID b: String, title: String) -> Bool {
            if let bundleID, bundleID != b { return false }
            let p = pattern.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return false }
            return PrivateList.glob(p, title)
        }
    }

    /// Bundle ids of private apps.
    public var apps: [String]
    public var titles: [TitleRule]

    public init(apps: [String] = PrivateList.defaultApps, titles: [TitleRule] = []) {
        self.apps = apps; self.titles = titles
    }

    /// Mail, Messages, Slack and WhatsApp (both the App Store and the older desktop app).
    public static let defaultApps = ["com.apple.mail", "com.apple.MobileSMS", "com.tinyspeck.slackmacgap",
                                     "net.whatsapp.WhatsApp", "desktop.WhatsApp"]

    /// SO-111: adds an app once.
    public mutating func addApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        apps.append(bundleID)
    }

    public mutating func removeApp(_ bundleID: String) { apps.removeAll { $0 == bundleID } }

    /// SO-111: adds a title rule once; blank patterns are ignored. Returns false when nothing was added.
    @discardableResult
    public mutating func addTitle(_ pattern: String, bundleID: String? = nil) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        let rule = TitleRule(bundleID: bundleID?.isEmpty == true ? nil : bundleID, pattern: p)
        guard !p.isEmpty, !titles.contains(rule) else { return false }
        titles.append(rule)
        return true
    }

    public mutating func removeTitle(_ rule: TitleRule) { titles.removeAll { $0 == rule } }

    public func isPrivate(bundleID: String, title: String) -> Bool {
        apps.contains(bundleID) || titles.contains { $0.matches(bundleID: bundleID, title: title) }
    }

    /// Case-insensitive match. With `*`, the whole title must match; without, it must contain the pattern.
    static func glob(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        guard p.contains("*") else { return text.localizedCaseInsensitiveContains(pattern) }
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] != "*", p[pi] == t[ti] { pi += 1; ti += 1 }
            else if pi < p.count, p[pi] == "*" { star = pi; mark = ti; pi += 1 }
            else if star >= 0 { pi = star + 1; mark += 1; ti = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

/// SO-110: whether Meeting mode is on, and whether screen sharing turned it on.
public struct MeetingState: Sendable, Equatable {
    public private(set) var on = false
    /// True when sharing turned it on, so it turns off again when sharing stops.
    public private(set) var auto = false

    public init() {}

    /// By hand, a rule or a scene. Sharing stopping won't turn it off after this.
    public mutating func set(_ on: Bool) {
        self.on = on
        auto = false
    }

    /// Screen sharing started or stopped. Returns the new value when it changed.
    public mutating func sharing(_ sharing: Bool, autoEnabled: Bool) -> Bool? {
        if sharing, autoEnabled, !on { on = true; auto = true; return true }
        if !sharing, on, auto { on = false; auto = false; return false }
        return nil
    }
}

/// SO-110: is the screen being shared? macOS has no public API, so this looks at the session
/// (macOS Screen Sharing) and at the windows meeting apps show while sharing.
public enum SharingDetector {
    /// An on-screen window: owning app's name and the window's title.
    public struct Window: Sendable {
        public var owner: String
        public var title: String
        public init(owner: String, title: String) { self.owner = owner; self.title = title }
    }

    public static func isSharing(sessionShared: Bool, windows: [Window]) -> Bool {
        sessionShared || windows.contains(where: marker)
    }

    static func marker(_ w: Window) -> Bool {
        let owner = w.owner.lowercased(), title = w.title.lowercased()
        // Chrome, Edge, Brave, Arc: "meet.google.com is sharing your screen." / "… a window."
        if title.contains(" is sharing your screen") || title.contains(" is sharing a window")
            || title.contains(" is sharing a tab") { return true }
        // Zoom's share toolbar.
        if owner == "zoom.us", title.contains("share") && (title.contains("toolbar") || title.contains("statusbar")) { return true }
        // Teams' sharing control bar.
        if owner.contains("teams"), title.contains("sharing control bar") { return true }
        // Slack huddles and Webex: "You're sharing your screen" banners.
        if title.contains("you're sharing") || title.contains("you’re sharing") || title.contains("you are sharing") { return true }
        return false
    }
}
