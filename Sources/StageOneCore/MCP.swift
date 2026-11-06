import Foundation

/// SO-121: `stage mcp`, a Model Context Protocol server over stdio (JSON-RPC 2.0, one message
/// per line). Pure: it turns a request line into a reply line, running `Command`s through `send`.
public enum MCPServer {
    public static let protocolVersion = "2025-06-18"

    public struct Tool: Sendable {
        public var name: String
        public var description: String
        /// Changes the desk, so Stage One asks first unless the user allowed it for good.
        public var changesDesk: Bool
        public var params: [(name: String, description: String, enumValues: [String]?)]
    }

    public static let tools: [Tool] = [
        Tool(name: "list_scenes", description: "List saved scenes: name, groups, windows, when saved, and which is current.",
             changesDesk: false, params: []),
        Tool(name: "restore_scene", description: "Restore a saved scene: put its groups and windows back. Fuzzy-matches the name.",
             changesDesk: true, params: [("name", "Scene name, or part of it.", nil)]),
        Tool(name: "save_scene", description: "Save the current desk (every group and window) as a scene.",
             changesDesk: false, params: [("name", "Name for the new scene.", nil)]),
        Tool(name: "list_groups", description: "List window groups on the desk, with window counts and which is on stage.",
             changesDesk: false, params: []),
        Tool(name: "arrange", description: "Arrange the windows on stage in a layout.",
             changesDesk: true, params: [("layout", "The layout.", LayoutKind.allCases.map(\.rawValue))]),
        Tool(name: "rewind_points", description: "List the times the desk can be rewound to (snapshots from the last 7 days).",
             changesDesk: false, params: []),
    ]

    /// Tools the user can allow without asking (Settings › Integrations).
    public static var askingTools: [String] { tools.filter(\.changesDesk).map(\.name) }

    /// Handles one line. Returns the reply line, or nil for notifications.
    public static func handle(_ line: Data, send: (Command) throws -> CommandReply) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: line), let req = obj as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        let id = req["id"]
        let method = req["method"] as? String ?? ""
        let params = req["params"] as? [String: Any] ?? [:]
        // Notifications (no id) get no reply.
        guard let id else { return nil }

        func result(_ r: Any) -> Data? { encode(["jsonrpc": "2.0", "id": id, "result": r]) }
        func error(_ code: Int, _ message: String) -> Data? {
            encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            return result([
                "protocolVersion": asked ?? protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "stage-one", "title": "Stage One", "version": "0.1.0"],
                "instructions": "Stage One manages macOS windows in groups and saved scenes. Tools that move windows ask the user in Stage One first.",
            ])
        case "ping":
            return result([String: Any]())
        case "tools/list":
            return result(["tools": tools.map(schema)])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                return error(-32602, "Unknown tool: \(params["name"] as? String ?? "")")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return result(call(tool, args, send: send))
        default:
            return error(-32601, "Method not found: \(method)")
        }
    }

    static func schema(_ t: Tool) -> [String: Any] {
        var props: [String: Any] = [:]
        for p in t.params {
            var s: [String: Any] = ["type": "string", "description": p.description]
            if let e = p.enumValues { s["enum"] = e }
            props[p.name] = s
        }
        return [
            "name": t.name,
            "description": t.description + (t.changesDesk ? " Stage One asks the user to allow it unless they allowed it for good." : ""),
            "inputSchema": ["type": "object", "properties": props, "required": t.params.map(\.name)],
            "annotations": ["readOnlyHint": !t.changesDesk && t.name != "save_scene", "destructiveHint": false,
                            "idempotentHint": !t.changesDesk],
        ]
    }

    /// The command a tool call runs; desk-changing ones are wrapped in `.ask`.
    /// A tool's command, or why the arguments don't work.
    enum Plan: Equatable { case run(Command), invalid(String) }

    static func command(for tool: Tool, _ args: [String: Any]) -> Plan {
        func arg(_ k: String) -> String? {
            (args[k] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let c: Command
        switch tool.name {
        case "list_scenes": c = .list
        case "list_groups": c = .status
        case "rewind_points": c = .rewindPoints
        case "save_scene":
            guard let n = arg("name") else { return .invalid("save_scene needs a name.") }
            c = .save(name: n)
        case "restore_scene":
            guard let n = arg("name") else { return .invalid("restore_scene needs a name.") }
            c = .restore(scene: n)
        case "arrange":
            guard let l = arg("layout").flatMap(LayoutKind.init(loose:)) else {
                return .invalid("arrange needs a layout: \(LayoutKind.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            c = .layout(l)
        default: return .invalid("Unknown tool \(tool.name).")
        }
        return .run(tool.changesDesk ? .ask(tool: tool.name, command: c) : c)
    }

    static func call(_ tool: Tool, _ args: [String: Any], send: (Command) throws -> CommandReply) -> [String: Any] {
        let command: Command
        switch Self.command(for: tool, args) {
        case .invalid(let m): return text(m, isError: true)
        case .run(let c): command = c
        }
        let reply: CommandReply
        do { reply = try send(command) } catch {
            return text("\(error)", isError: true)
        }
        guard reply.ok else { return text(reply.message, isError: true) }
        var out = text(body(tool.name, reply), isError: false)
        if let structured = structured(tool.name, reply) { out["structuredContent"] = structured }
        return out
    }

    static func text(_ s: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": s]], "isError": isError]
    }

    static func iso(_ d: Date) -> String { d.formatted(.iso8601) }

    static func body(_ tool: String, _ r: CommandReply) -> String {
        switch tool {
        case "list_scenes":
            let s = r.scenes ?? []
            if s.isEmpty { return "No scenes saved yet." }
            return s.map { "- \($0.name): \($0.windows) windows in \($0.groups) groups\($0.current ? " (current)" : "")" }.joined(separator: "\n")
        case "list_groups":
            let g = r.groups ?? []
            if g.isEmpty { return "No groups." }
            return g.map { "\($0.index). \($0.name): \($0.windows) windows\($0.active ? " (on stage)" : "")" }.joined(separator: "\n")
        case "rewind_points":
            let p = r.points ?? []
            if p.isEmpty { return "No rewind points yet." }
            return p.map(iso).joined(separator: "\n")
        default:
            return r.message
        }
    }

    static func structured(_ tool: String, _ r: CommandReply) -> [String: Any]? {
        switch tool {
        case "list_scenes":
            return ["scenes": (r.scenes ?? []).map {
                ["name": $0.name, "groups": $0.groups, "windows": $0.windows, "savedAt": iso($0.savedAt), "current": $0.current] as [String: Any]
            }]
        case "list_groups":
            return ["groups": (r.groups ?? []).map { ["index": $0.index, "name": $0.name, "windows": $0.windows, "active": $0.active] as [String: Any] }]
        case "rewind_points":
            return ["points": (r.points ?? []).map(iso)]
        default:
            return nil
        }
    }

    static func encode(_ obj: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
