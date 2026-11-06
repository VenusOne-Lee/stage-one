import XCTest
@testable import StageOneCore

/// SO-121: the MCP server's JSON-RPC handling, with a fake app.
final class MCPTests: XCTestCase {
    var sent: [Command] = []

    func call(_ json: String, reply: CommandReply = CommandReply(ok: true, message: "ok")) -> [String: Any]? {
        let out = MCPServer.handle(Data(json.utf8)) { c in self.sent.append(c); return reply }
        return out.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testInitializeAndList() throws {
        let r = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
        let result = try XCTUnwrap(r["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])

        let l = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = try XCTUnwrap((l["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String },
                       ["list_scenes", "restore_scene", "save_scene", "list_groups", "arrange", "rewind_points"])
        XCTAssertTrue(sent.isEmpty)
    }

    func testNotificationGetsNoReply() {
        XCTAssertNil(call(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testErrors() throws {
        let bad = try XCTUnwrap(call("not json"))
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? Int, -32700)
        let missing = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#))
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? Int, -32601)
        let tool = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nope"}}"#))
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testDeskChangingToolsAsk() throws {
        _ = call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"restore_scene","arguments":{"name":"deep"}}}"#)
        _ = call(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"arrange","arguments":{"layout":"halves"}}}"#)
        _ = call(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"save_scene","arguments":{"name":"Calls"}}}"#)
        XCTAssertEqual(sent, [.ask(tool: "restore_scene", command: .restore(scene: "deep")),
                              .ask(tool: "arrange", command: .layout(.halves)),
                              .save(name: "Calls")])
        XCTAssertEqual(MCPServer.askingTools, ["restore_scene", "arrange"])
    }

    func testMissingArgumentIsToolError() throws {
        let r = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"arrange","arguments":{"layout":"zigzag"}}}"#))
        let result = try XCTUnwrap(r["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(sent.isEmpty)
    }

    func testListScenesText() throws {
        let reply = CommandReply(ok: true, message: "1 scene",
                                 scenes: [SceneSummary(name: "Deep work", slug: "deep-work", groups: 2, windows: 5,
                                                       savedAt: Date(timeIntervalSince1970: 0), current: true)])
        let r = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"list_scenes"}}"#, reply: reply))
        let result = try XCTUnwrap(r["result"] as? [String: Any])
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertEqual(text, "- Deep work: 5 windows in 2 groups (current)")
        XCTAssertNotNil(result["structuredContent"])
        XCTAssertEqual(sent, [.list])
    }

    func testDeclinedIsToolError() throws {
        let r = try XCTUnwrap(call(#"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"restore_scene","arguments":{"name":"x"}}}"#,
                                   reply: .fail("Declined in Stage One.")))
        XCTAssertEqual((r["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testAskCommandRoundTrips() throws {
        let c = Command.ask(tool: "arrange", command: .layout(.grid))
        XCTAssertEqual(try IPC.decode(Command.self, IPC.encode(c)), c)
    }
}
