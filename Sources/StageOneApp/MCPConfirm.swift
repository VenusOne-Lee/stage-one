import AppKit
import StageOneCore

/// SO-121: the toast that asks before an AI assistant moves windows.
@MainActor
enum MCPConfirm {
    static func ask(tool: String, _ command: Command, answer: CommandServer.Answer) {
        Toast.shared.show("An AI assistant wants to \(describe(command))",
                          detail: "Ignore this to say no.",
                          action: (title: "Allow", run: { answer.allow() }), duration: 20)
    }

    static func describe(_ c: Command) -> String {
        switch c {
        case .restore(let s): return "restore “\(s)”"
        case .layout(let k): return "arrange the stage: \(k.title)"
        default: return "change your desk"
        }
    }

    /// Settings label for an asking tool.
    static func title(_ tool: String) -> String {
        switch tool {
        case "restore_scene": return "Restore a scene (restore_scene)"
        case "arrange": return "Arrange the stage (arrange)"
        default: return tool
        }
    }
}
