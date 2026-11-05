import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Every action the app can take from outside: the `stage` CLI, `stageone://` URLs,
/// App Intents, Alfred and the MCP server all go through this one bus.
public enum Command: Codable, Sendable, Equatable {
    case list
    case save(name: String)
    case restore(scene: String)
    case group(String)
    case layout(LayoutKind)
    case rewind(to: Date?)
    case export(scene: String, path: String, includeFiles: Bool)
    case importScene(path: String)
    case status
    case pause(Bool)

    /// Parses `stageone://<verb>?k=v` URLs (SO-101).
    public init?(url: URL) {
        guard url.scheme == "stageone" else { return nil }
        let verb = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
        switch verb {
        case "list": self = .list
        case "status": self = .status
        case "save": self = .save(name: q("name") ?? q("scene") ?? "Untitled")
        case "restore": guard let s = q("scene") ?? q("name") else { return nil }; self = .restore(scene: s)
        case "group": guard let g = q("group") ?? q("name") ?? q("index") else { return nil }; self = .group(g)
        case "layout": guard let k = (q("kind") ?? q("layout")).flatMap(LayoutKind.init(loose:)) else { return nil }; self = .layout(k)
        case "rewind": self = .rewind(to: q("to").flatMap { ISO8601DateFormatter().date(from: $0) })
        case "import": guard let p = q("path") else { return nil }; self = .importScene(path: p)
        case "pause": self = .pause(q("on") != "false")
        default: return nil
        }
    }

    /// Commands that change the desk and need a confirmation when they come from a URL.
    public var isDestructive: Bool {
        switch self {
        case .restore, .rewind, .importScene: return true
        default: return false
        }
    }
}

/// What the app sends back to the CLI.
public struct CommandReply: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var scenes: [SceneSummary]?
    public var groups: [GroupSummary]?
    public var layouts: [String]?

    public init(ok: Bool, message: String, scenes: [SceneSummary]? = nil, groups: [GroupSummary]? = nil, layouts: [String]? = nil) {
        self.ok = ok; self.message = message; self.scenes = scenes; self.groups = groups; self.layouts = layouts
    }

    public static func fail(_ m: String) -> CommandReply { CommandReply(ok: false, message: m) }
}

public struct SceneSummary: Codable, Sendable, Equatable {
    public var name: String
    public var slug: String
    public var groups: Int
    public var windows: Int
    public var savedAt: Date
    public var current: Bool

    public init(name: String, slug: String, groups: Int, windows: Int, savedAt: Date, current: Bool) {
        self.name = name; self.slug = slug; self.groups = groups; self.windows = windows; self.savedAt = savedAt; self.current = current
    }
}

public struct GroupSummary: Codable, Sendable, Equatable {
    public var index: Int
    public var name: String
    public var windows: Int
    public var active: Bool

    public init(index: Int, name: String, windows: Int, active: Bool) {
        self.index = index; self.name = name; self.windows = windows; self.active = active
    }
}

/// Where the app and the CLI meet. A Unix domain socket keeps the CLI dependency-free
/// and works for unsigned dev builds, where a Mach XPC service cannot be registered.
public enum IPC {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("StageOne", isDirectory: true)
    }
    public static var scenesDirectory: URL { supportDirectory.appendingPathComponent("Scenes", isDirectory: true) }
    public static var socketPath: String { supportDirectory.appendingPathComponent("stage.sock").path }

    public static func encode<T: Encodable>(_ v: T) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try e.encode(v)
    }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(t, from: d)
    }
}
