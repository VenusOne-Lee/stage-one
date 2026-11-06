import AppKit
import StageOneCore
import UniformTypeIdentifiers

/// SO-120: export a scene as a `.stagescene` file, and import one by opening it.
@MainActor
enum SceneFiles {
    /// Asks where to save, with "Include files" off: document paths and the wallpaper stay out.
    static func export(_ scene: StageScene) {
        let panel = NSSavePanel()
        panel.title = "Export “\(scene.name)”"
        panel.nameFieldStringValue = "\(scene.name).\(StageScene.fileExtension)"
        panel.allowedContentTypes = [UTType(exportedAs: "africa.venusone.stagescene")]
        let include = NSButton(checkboxWithTitle: "Include files (document paths and wallpaper)", target: nil, action: nil)
        include.state = .off
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 34))
        include.frame = NSRect(x: 16, y: 8, width: 340, height: 18)
        box.addSubview(include)
        panel.accessoryView = box
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let out = include.state == .on ? scene : scene.strippingDocuments()
        do {
            try out.encoded().write(to: url, options: .atomic)
            Toast.shared.show("Exported “\(scene.name)”", detail: url.lastPathComponent,
                              action: (title: "Show", run: { NSWorkspace.shared.activateFileViewerSelecting([url]) }), duration: 5)
        } catch {
            Toast.shared.show("Couldn't export “\(scene.name)”", detail: error.localizedDescription, duration: 5)
        }
    }

    /// Double-clicked `.stagescene` files. Each is added to Scenes; a taken name gets a number,
    /// and its rule starts off so a shared file never moves windows by itself.
    static func open(_ urls: [URL]) {
        let store = SceneStore.shared
        var imported: [StageScene] = []
        var failed: [String] = []
        for url in urls {
            do {
                store.reload()
                let scene = try StageScene.decode(Data(contentsOf: url))
                    .preparedForImport(existingNames: store.scenes.map(\.name))
                try store.write(scene)
                imported.append(scene)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        if let s = imported.first, imported.count == 1 {
            let ruleNote = s.rule != nil ? "Its rule is off until you turn it on in Rules." : nil
            Toast.shared.show("Imported “\(s.name)”", detail: ruleNote,
                              action: (title: "Restore", run: { SceneRestore.restore(s) }), duration: 8)
        } else if !imported.isEmpty {
            Toast.shared.show("Imported \(imported.count) scenes", detail: imported.map(\.name).joined(separator: ", "), duration: 5)
        }
        if !failed.isEmpty {
            Toast.shared.show("Not a Stage One scene", detail: failed.joined(separator: ", "), duration: 5)
        }
    }
}
