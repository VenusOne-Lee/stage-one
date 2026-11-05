import ArgumentParser
import Foundation
import StageOneCore

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List saved scenes and the groups on your desk.")
    @OptionGroup var output: Output

    func run() throws {
        try runCommand(.list, output) { r in
            let scenes = r.scenes ?? []
            print("Scenes")
            if scenes.isEmpty { print("  none yet. Save one with: stage save \"Name\"") }
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            for s in scenes {
                let mark = s.current ? "●" : " "
                print("  \(mark) \(s.name.padding(toLength: max(s.name.count, 28), withPad: " ", startingAt: 0))  \(s.groups) groups · \(s.windows) windows · \(df.string(from: s.savedAt))")
            }
            print("\nGroups")
            for g in r.groups ?? [] {
                let mark = g.active ? "●" : " "
                print("  \(mark) \(g.index)  \(g.name) (\(g.windows) windows)")
            }
            if let l = r.layouts { print("\nLayouts: \(l.joined(separator: ", "))") }
        }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what's on stage.")
    @OptionGroup var output: Output
    func run() throws { try runCommand(.status, output) }
}

struct Save: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Save the desk as a scene.")
    @Argument(help: "Scene name.") var name: [String]
    @OptionGroup var output: Output
    func run() throws { try runCommand(.save(name: name.joined(separator: " ")), output) }
}

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Restore a saved scene. Fuzzy names work.")
    @Argument(help: "Scene name.") var scene: [String]
    @OptionGroup var output: Output
    func run() throws { try runCommand(.restore(scene: scene.joined(separator: " ")), output) }
}

struct GroupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "group", abstract: "Put a group on stage by number or name.")
    @Argument(help: "Group number (1–9) or name.") var group: [String]
    @OptionGroup var output: Output
    func run() throws { try runCommand(.group(group.joined(separator: " ")), output) }
}

struct Layout: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Arrange the windows on stage: free, halves, focus, thirds, grid.")
    @Argument(help: "Layout name.") var kind: String
    @OptionGroup var output: Output
    func validate() throws {
        guard LayoutKind(loose: kind) != nil else {
            throw ValidationError("Unknown layout “\(kind)”. Use one of: \(LayoutKind.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
    }
    func run() throws { try runCommand(.layout(LayoutKind(loose: kind)!), output) }
}

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Write a scene to a .stagescene file you can share.")
    @Argument(help: "Scene name.") var scene: String
    @Argument(help: "File or folder to write to.") var path = "."
    @Flag(help: "Keep document paths in the file (left out by default for privacy).") var includeFiles = false
    @OptionGroup var output: Output
    func run() throws {
        let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath,
                       relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).path
        try runCommand(.export(scene: scene, path: full, includeFiles: includeFiles), output)
    }
}

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add a .stagescene file to your scenes.")
    @Argument(help: "Path to a .stagescene file.") var path: String
    @OptionGroup var output: Output
    func run() throws {
        let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath,
                       relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).path
        try runCommand(.importScene(path: full), output)
    }
}

struct Pause: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Pause Stage One and give windows back to macOS.")
    @OptionGroup var output: Output
    func run() throws { try runCommand(.pause(true), output) }
}

struct Resume: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Resume Stage One.")
    @OptionGroup var output: Output
    func run() throws { try runCommand(.pause(false), output) }
}

struct Rewind: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Put the desk back the way it was at an earlier time.")
    @Option(help: "When to go back to, as ISO 8601 (2026-11-05T14:30:00Z) or minutes ago (15m).") var to: String?
    @OptionGroup var output: Output

    func run() throws {
        var date: Date?
        if let t = to {
            if t.hasSuffix("m"), let m = Double(t.dropLast()) {
                date = Date().addingTimeInterval(-m * 60)
            } else if let d = ISO8601DateFormatter().date(from: t) {
                date = d
            } else {
                throw ValidationError("Use an ISO 8601 time or minutes ago, like 15m.")
            }
        }
        try runCommand(.rewind(to: date), output)
    }
}
