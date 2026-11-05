import AppKit

/// The panels the menu bar item, hotkeys and command bar can open.
enum PanelKind { case saveScene, scenes, rewind, view, rules, commandBar }

/// One place to open panels. Features register a handler per kind; until one is
/// registered, `show` says the panel is coming soon.
@MainActor final class Panels {
    static let shared = Panels()
    var handlers: [PanelKind: () -> Void] = [:]

    func show(_ kind: PanelKind) {
        if let handler = handlers[kind] {
            handler()
            return
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Coming soon"
        alert.informativeText = "\(Panels.title(of: kind)) isn't built yet. It is on the way in an upcoming version of Stage One."
        alert.icon = Mark.image(size: 64)
        alert.addButton(withTitle: "OK")
        alert.window.appearance = NSAppearance(named: .aqua)
        alert.runModal()
    }

    private static func title(of kind: PanelKind) -> String {
        switch kind {
        case .saveScene: return "Save scene"
        case .scenes: return "Scenes"
        case .rewind: return "Rewind"
        case .view: return "View"
        case .rules: return "Rules"
        case .commandBar: return "The command bar"
        }
    }
}
