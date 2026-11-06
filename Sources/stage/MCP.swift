import ArgumentParser
import Foundation
import StageOneCore

/// SO-121: `stage mcp` runs a Model Context Protocol server over stdio, so AI assistants
/// can list, save and restore scenes. Tools that move windows ask in Stage One first.
struct MCP: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run an MCP server over stdio for AI assistants.",
        discussion: """
        Add to your MCP client's config, for example:
          { "mcpServers": { "stage-one": { "command": "/usr/local/bin/stage", "args": ["mcp"] } } }
        Tools: list_scenes, restore_scene, save_scene, list_groups, arrange, rewind_points.
        restore_scene and arrange ask in Stage One unless allowed in Settings › Integrations.
        """
    )

    func run() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let out = MCPServer.handle(Data(line.utf8), send: { try Client.send($0) }) else { continue }
            FileHandle.standardOutput.write(out + Data([10]))
        }
    }
}
