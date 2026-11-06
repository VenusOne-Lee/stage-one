import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// SO-054: glass panel with the save box on top and scene cards below.
@MainActor
enum ScenesPanel {
    private static var panel: GlassPanel?

    static func show() {
        if let p = panel, p.isVisible { p.makeKeyAndOrderFront(nil); return }
        SceneStore.shared.reload()
        let p = GlassPanel(size: CGSize(width: 520, height: 600)) {
            ScenesView(store: SceneStore.shared, prefs: Preferences.shared, close: { ScenesPanel.panel?.close() })
        }
        panel = p
        p.present()
    }
}

struct ScenesView: View {
    @ObservedObject var store: SceneStore
    @ObservedObject var prefs: Preferences
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(nsImage: Mark.image(size: 20))
                Text("Scenes").font(Theme.display(22)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.scenes.count) saved").font(.system(size: 11)).foregroundStyle(Theme.ink3)
            }
            SaveSceneBox(onDone: {})
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.glass))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
            if store.scenes.isEmpty {
                VStack(spacing: 6) {
                    Text("No scenes yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                    Text("Save this desk and you can bring it back after a restart, a new monitor or a messy afternoon.")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink3).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.scenes) { scene in
                            SceneCard(scene: scene, onStage: prefs.currentScene == scene.name, edited: prefs.sceneEdited)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
    }
}

struct SceneCard: View {
    let scene: StageScene
    let onStage: Bool
    let edited: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            MiniDesk(scene: scene).frame(width: 112, height: 70)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(scene.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    if onStage && edited { Text("· edited").font(.system(size: 12)).foregroundStyle(Theme.spot) }
                }
                Text("\(scene.groups.filter { !$0.windows.isEmpty }.count) groups · \(scene.windowCount) windows · \(scene.savedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11)).foregroundStyle(Theme.ink3)
                HStack(spacing: 4) {
                    if let rule = scene.rule { Chip(text: ruleTitle(rule)) }
                    if scene.options.dnd { Chip(text: "Do Not Disturb") }
                    if scene.options.meetingMode { Chip(text: "Meeting mode") }
                    if scene.options.hideOthers { Chip(text: "Hides other apps") }
                    if scene.options.closeOthers { Chip(text: "Quits other apps") }
                    if scene.options.wallpaper != nil { Chip(text: "Wallpaper") }
                }
            }
            Spacer()
            if onStage {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("On stage").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.spot)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.spotSoft))
                    if edited {
                        Button("Update") { SceneEdited.updateCurrent() }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.focus)
                    }
                }
            } else {
                Button { SceneRestore.restore(scene) } label: {
                    Text("Restore").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.spot))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Color.white.opacity(0.9) : Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(onStage ? Theme.spot.opacity(0.5) : Theme.line))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Restore") { SceneRestore.restore(scene) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([SceneStore.shared.url(for: scene)]) }
            Button("Export…") { SceneFiles.export(scene) }
            Divider()
            Button("Delete") { SceneStore.shared.delete(scene) }
        }
    }

    private func ruleTitle(_ r: StageScene.Rule) -> String {
        switch r.type {
        case "displayConnected": return "Display connects"
        case "displayDisconnected": return "Display unplugs"
        case "focus": return "Focus"
        case "appLaunched": return "App opens"
        case "time": return "Time"
        case "calendar": return "Calendar"
        case "wifi": return "Wi-Fi"
        default: return r.type
        }
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.ink2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.page))
    }
}

/// A schematic of the scene's desk: the active group's windows, with the strip on its edge.
struct MiniDesk: View {
    let scene: StageScene

    var body: some View {
        GeometryReader { geo in
            let display = scene.displays.first
            let bounds = display.map { CGRect(array: $0.frame) } ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let sx = geo.size.width / max(bounds.width, 1), sy = geo.size.height / max(bounds.height, 1)
            let active = scene.groups.indices.contains(scene.active) ? scene.groups[scene.active] : scene.groups.first
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Theme.spotSoft, Theme.page], startPoint: .top, endPoint: .bottom))
                stripShape(display?.strip ?? .left, size: geo.size)
                ForEach(Array((active?.windows ?? []).prefix(8).enumerated()), id: \.offset) { _, w in
                    let f = w.cgFrame
                    RoundedRectangle(cornerRadius: 2).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.line))
                        .frame(width: max(4, f.width * sx), height: max(3, f.height * sy))
                        .offset(x: (f.minX - bounds.minX) * sx, y: (f.minY - bounds.minY) * sy)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func stripShape(_ edge: ScreenEdge, size: CGSize) -> some View {
        let t: CGFloat = 10
        switch edge {
        case .left: RoundedRectangle(cornerRadius: 2).fill(Theme.spot.opacity(0.35)).frame(width: t, height: size.height - 8).offset(x: 3, y: 4)
        case .right: RoundedRectangle(cornerRadius: 2).fill(Theme.spot.opacity(0.35)).frame(width: t, height: size.height - 8).offset(x: size.width - t - 3, y: 4)
        case .top: RoundedRectangle(cornerRadius: 2).fill(Theme.spot.opacity(0.35)).frame(width: size.width - 8, height: t * 0.7).offset(x: 4, y: 3)
        case .bottom: RoundedRectangle(cornerRadius: 2).fill(Theme.spot.opacity(0.35)).frame(width: size.width - 8, height: t * 0.7).offset(x: 4, y: size.height - t * 0.7 - 3)
        }
    }
}
