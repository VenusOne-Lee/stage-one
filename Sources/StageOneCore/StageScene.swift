import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The `.stagescene` file format, version 1 (see docs/BACKLOG.md, "Data model").
public struct StageScene: Codable, Sendable, Equatable, Identifiable {
    public static let currentVersion = 1
    public static let fileExtension = "stagescene"

    public var id: String { slug }
    public var version: Int
    public var name: String
    public var savedAt: Date
    public var displays: [Display]
    public var groups: [Group]
    public var active: Int
    public var rule: Rule?
    public var options: Options

    public struct Display: Codable, Sendable, Equatable {
        public var id: String
        public var frame: [Double]
        public var strip: ScreenEdge
        public var dock: ScreenEdge
        public var mode: OverlapMode
        public var size: StripSize
        /// The usable area the scene was saved in, so it can be reflowed on restore (SO-035).
        public var usable: [Double]?

        public init(id: String, frame: [Double], strip: ScreenEdge, dock: ScreenEdge, mode: OverlapMode, size: StripSize, usable: [Double]? = nil) {
            self.id = id; self.frame = frame; self.strip = strip; self.dock = dock; self.mode = mode; self.size = size; self.usable = usable
        }

        public init(_ layout: ScreenLayout) {
            self.init(id: layout.displayID, frame: layout.frame.array, strip: layout.stripEdge, dock: layout.dockEdge,
                      mode: layout.mode, size: layout.size, usable: layout.usableFrame.array)
        }
    }

    public struct Group: Codable, Sendable, Equatable {
        public var name: String
        public var color: String
        public var display: String?
        public var layout: LayoutKind
        public var windows: [Window]

        public init(name: String, color: String, display: String?, layout: LayoutKind, windows: [Window]) {
            self.name = name; self.color = color; self.display = display; self.layout = layout; self.windows = windows
        }
    }

    public struct Window: Codable, Sendable, Equatable {
        public var bundleId: String
        public var appName: String?
        public var title: String
        public var document: String?
        public var frame: [Double]
        public var relaunch: String?

        public init(bundleId: String, appName: String? = nil, title: String, document: String?, frame: [Double], relaunch: String? = nil) {
            self.bundleId = bundleId; self.appName = appName; self.title = title; self.document = document; self.frame = frame; self.relaunch = relaunch
        }

        public init(_ w: WindowSnapshot) {
            self.init(bundleId: w.bundleID, appName: w.appName, title: w.title, document: w.document, frame: w.frame.array)
        }

        public var cgFrame: CGRect { CGRect(array: frame) }
    }

    /// When a scene restores itself (SO-070). `type` is a `RuleTrigger` raw value; the
    /// other fields are that trigger's parameter. Older files have only type and display.
    public struct Rule: Codable, Sendable, Equatable {
        public var type: String
        /// displayConnected / displayDisconnected: the display's stable id.
        public var display: String?
        /// appLaunched: bundle id.
        public var app: String?
        /// time: "HH:mm", 24-hour.
        public var time: String?
        /// focus: the Focus name; calendar: a title keyword or calendar name; wifi: network name.
        public var match: String?
        /// Rules can be switched off without deleting them.
        public var enabled: Bool

        public init(type: String, display: String? = nil, app: String? = nil, time: String? = nil,
                    match: String? = nil, enabled: Bool = true) {
            self.type = type; self.display = display; self.app = app; self.time = time
            self.match = match; self.enabled = enabled
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            display = try c.decodeIfPresent(String.self, forKey: .display)
            app = try c.decodeIfPresent(String.self, forKey: .app)
            time = try c.decodeIfPresent(String.self, forKey: .time)
            match = try c.decodeIfPresent(String.self, forKey: .match)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    public struct Options: Codable, Sendable, Equatable {
        public var dnd: Bool
        public var meetingMode: Bool
        /// SO-055: hide apps with no window in the scene.
        public var hideOthers: Bool
        /// SO-055: quit apps with no window in the scene (Stage One asks first).
        public var closeOthers: Bool
        /// SO-055: path of an image to use as the desktop picture.
        public var wallpaper: String?

        public init(dnd: Bool = false, meetingMode: Bool = false, hideOthers: Bool = false,
                    closeOthers: Bool = false, wallpaper: String? = nil) {
            self.dnd = dnd; self.meetingMode = meetingMode; self.hideOthers = hideOthers
            self.closeOthers = closeOthers; self.wallpaper = wallpaper
        }

        // Scenes saved before SO-055 only have dnd and meetingMode.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dnd = try c.decodeIfPresent(Bool.self, forKey: .dnd) ?? false
            meetingMode = try c.decodeIfPresent(Bool.self, forKey: .meetingMode) ?? false
            hideOthers = try c.decodeIfPresent(Bool.self, forKey: .hideOthers) ?? false
            closeOthers = try c.decodeIfPresent(Bool.self, forKey: .closeOthers) ?? false
            wallpaper = try c.decodeIfPresent(String.self, forKey: .wallpaper)
        }

        /// True when restoring changes something beyond windows.
        public var isEmpty: Bool { !dnd && !meetingMode && !hideOthers && !closeOthers && wallpaper == nil }
    }

    /// SO-055: apps that have no window in this scene, from those running.
    public func appsNotInScene(running: [String]) -> [String] {
        let inScene = Set(groups.flatMap { $0.windows.map(\.bundleId) })
        return running.filter { !inScene.contains($0) }
    }

    public init(name: String, savedAt: Date = Date(), displays: [Display], groups: [Group], active: Int,
                rule: Rule? = nil, options: Options = Options()) {
        self.version = StageScene.currentVersion
        self.name = name; self.savedAt = savedAt; self.displays = displays; self.groups = groups
        self.active = active; self.rule = rule; self.options = options
    }

    /// Builds a scene from the live desk.
    public init(name: String, desk: Desk, windows: [UInt32: WindowSnapshot], layouts: [ScreenLayout], savedAt: Date = Date()) {
        let groups = desk.groups.map { g in
            Group(name: g.name, color: g.color, display: g.displayID, layout: g.layout,
                  windows: g.windowIDs.compactMap { windows[$0] }.map(Window.init))
        }
        self.init(name: name, savedAt: savedAt, displays: layouts.map(Display.init), groups: groups, active: desk.activeIndex ?? 0)
    }

    public var windowCount: Int { groups.reduce(0) { $0 + $1.windows.count } }

    public var slug: String { StageScene.slug(for: name) }

    public static func slug(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let parts = name.lowercased().unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let collapsed = parts.split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "scene" : collapsed
    }

    // MARK: Coding

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public func encoded() throws -> Data { try StageScene.encoder().encode(self) }
    public static func decode(_ data: Data) throws -> StageScene { try decoder().decode(StageScene.self, from: data) }

    /// A structural fingerprint ignoring time, used for "· edited" and snapshot dedupe.
    public func fingerprint() -> String {
        groups.map { g in
            g.name + "|" + g.layout.rawValue + "|" + g.windows.map { w in
                w.bundleId + ":" + w.title + ":" + w.frame.map { String(Int($0 / 4)) }.joined(separator: ",")
            }.joined(separator: ";")
        }.joined(separator: "\n") + "#\(active)"
    }

    /// Copy without document paths (SO-120 export default).
    public func strippingDocuments() -> StageScene {
        var s = self
        for g in s.groups.indices { for w in s.groups[g].windows.indices { s.groups[g].windows[w].document = nil } }
        return s
    }
}
