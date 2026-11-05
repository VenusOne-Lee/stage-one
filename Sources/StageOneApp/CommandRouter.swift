import AppKit
import StageOneCore
import WindowKit

/// SO-100 / SO-101: runs a `Command` against the live app. The `stage` CLI (over the
/// socket) and `stageone://` URLs both end up here.
@MainActor
enum CommandRouter {
    /// Pausing is owned by the engine; the menu bar wires this up. Defaults to the preference.
    static var setPaused: (Bool) -> Void = { Preferences.shared.paused = $0 }

    static func run(_ command: Command) -> CommandReply {
        let c = StageController.shared
        let store = SceneStore.shared
        switch command {
        case .status:
            let g = groupSummaries()
            let active = c.desk.active?.name ?? "none"
            let scene = Preferences.shared.currentScene.map { "“\($0)”\(Preferences.shared.sceneEdited ? " (edited)" : "")" } ?? "none"
            let paused = Preferences.shared.paused ? "paused" : "running"
            return CommandReply(ok: true, message: "Stage One \(paused). Active group: \(active). Scene: \(scene). \(g.count) groups, \(c.inventory.windows.count) windows.", groups: g)

        case .list:
            store.reload()
            let current = Preferences.shared.currentScene
            let scenes = store.scenes.map {
                SceneSummary(name: $0.name, slug: $0.slug, groups: $0.groups.filter { !$0.windows.isEmpty }.count,
                             windows: $0.windowCount, savedAt: $0.savedAt, current: $0.name == current)
            }
            return CommandReply(ok: true, message: "\(scenes.count) scene\(scenes.count == 1 ? "" : "s")",
                                scenes: scenes, groups: groupSummaries(), layouts: LayoutKind.allCases.map(\.rawValue))

        case .save(let name):
            guard let s = Scenes.save(name: name) else { return .fail("Couldn't save “\(name)”.") }
            return CommandReply(ok: true, message: "Saved “\(s.name)”: \(s.windowCount) windows.")

        case .restore(let query):
            store.reload()
            guard let s = store.scene(named: query) else { return .fail("No scene matches “\(query)”. Try `stage list`.") }
            let o = SceneRestore.restore(s)
            let missing = o.missing.isEmpty ? "" : " \(o.missing.count) not open yet, relaunching."
            return CommandReply(ok: true, message: "Restored “\(s.name)”: placed \(o.placed) windows.\(missing)")

        case .group(let query):
            guard let id = group(matching: query) else { return .fail("No group matches “\(query)”.") }
            c.switchTo(id)
            return CommandReply(ok: true, message: "On stage: \(c.desk.active?.name ?? query)")

        case .layout(let kind):
            LayoutService.apply(kind)
            return CommandReply(ok: true, message: "Layout: \(kind.title)")

        case .rewind:
            if let handler = rewind { return handler(command) }
            return .fail("Rewind isn't in this build yet.")

        case .export(let query, let path, let includeFiles):
            store.reload()
            guard var s = store.scene(named: query) else { return .fail("No scene matches “\(query)”.") }
            if !includeFiles { s = s.strippingDocuments() }
            var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                url = url.appendingPathComponent(s.slug).appendingPathExtension(StageScene.fileExtension)
            }
            do { try s.encoded().write(to: url, options: .atomic) } catch { return .fail(error.localizedDescription) }
            return CommandReply(ok: true, message: "Exported “\(s.name)” to \(url.path)")

        case .importScene(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            do {
                let s = try StageScene.decode(Data(contentsOf: url))
                try store.write(s)
                return CommandReply(ok: true, message: "Imported “\(s.name)”. Restore it with `stage restore \"\(s.name)\"`.")
            } catch {
                return .fail("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
            }

        case .pause(let on):
            setPaused(on)
            return CommandReply(ok: true, message: on ? "Paused. Windows are back where macOS put them." : "Resumed.")
        }
    }

    /// Hook for SO-060 (Rewind).
    static var rewind: ((Command) -> CommandReply)?

    static func groupSummaries() -> [GroupSummary] {
        let d = StageController.shared.desk
        return d.groups.enumerated().map { i, g in
            GroupSummary(index: i + 1, name: g.name, windows: g.windowIDs.count, active: g.id == d.activeID)
        }
    }

    /// A group by 1-based strip number, exact name, or fuzzy name.
    static func group(matching query: String) -> UUID? {
        let d = StageController.shared.desk
        let groups = d.groups
        if let n = Int(query), groups.indices.contains(n - 1) { return groups[n - 1].id }
        if let g = d.group(named: query) { return g.id }
        return Fuzzy.rank(groups, query: query, key: \.name).first?.id
    }
}
