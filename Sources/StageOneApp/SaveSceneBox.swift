import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// The Save box (⌘⇧S): name, trigger and options.
struct SaveSceneBox: View {
    var onDone: () -> Void = {}
    @State private var name = Scenes.suggestedName()
    @State private var trigger: SceneTrigger = .none
    @State private var dnd = false
    @State private var meeting = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save this desk").font(Theme.display(17)).foregroundStyle(Theme.ink)
            TextField("Scene name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? Theme.spot : Theme.line, lineWidth: focused ? 1.5 : 1))
                .focused($focused)
                .onSubmit(save)
            HStack(spacing: 8) {
                Picker("Restore when", selection: $trigger) {
                    ForEach(SceneTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Toggle("Do Not Disturb", isOn: $dnd).toggleStyle(.checkbox).tint(Theme.spot)
                Toggle("Meeting mode", isOn: $meeting).toggleStyle(.checkbox).tint(Theme.spot)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink2)
            HStack {
                let c = StageController.shared
                Text("\(c.desk.groups.filter { !$0.windowIDs.isEmpty }.count) groups · \(c.inventory.windows.count) windows")
                    .font(.system(size: 11)).foregroundStyle(Theme.ink3)
                Spacer()
                Button("Cancel", action: onDone).keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text("Save scene").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.spot))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        if Scenes.save(name: name, options: .init(dnd: dnd, meetingMode: meeting), rule: trigger.rule) != nil { onDone() }
    }
}

/// Triggers offered in the Save box (the rule engine arrives with SO-070).
enum SceneTrigger: String, CaseIterable {
    case none, displayConnected, focus, appLaunched, time

    var title: String {
        switch self {
        case .none: return "Restore by hand"
        case .displayConnected: return "When this display connects"
        case .focus: return "When a Focus starts"
        case .appLaunched: return "When an app opens"
        case .time: return "At a set time"
        }
    }

    var rule: StageScene.Rule? {
        switch self {
        case .none: return nil
        case .displayConnected: return .init(type: "displayConnected", display: ScreenLayouts.current()?.displayID)
        default: return .init(type: rawValue)
        }
    }
}

/// A floating glass panel hosting SwiftUI content, used for Save, Scenes, Rewind and Rules.
@MainActor
final class GlassPanel: NSPanel {
    init<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        let root = content()
            .padding(18)
            .frame(width: size.width)
            .background(VisualEffect().ignoresSafeArea())
            .environment(\.colorScheme, .light)
        contentView = NSHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }

    func present() {
        center()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

/// `.popover` vibrancy behind glass panels.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// ⌘⇧S anywhere opens the Save box.
@MainActor
enum SaveSceneHotKey {
    private static var id: UInt32?
    private static var panel: GlassPanel?

    static func install() {
        guard id == nil else { return }
        id = HotKeys.shared.register(.init(keyCode: 1 /* kVK_ANSI_S */, modifiers: HotKeys.command | HotKeys.shift)) {
            SaveSceneHotKey.showSaveBox()
        }
    }

    static func uninstall() {
        if let id { HotKeys.shared.unregister(id) }
        id = nil
    }

    static func showSaveBox() {
        panel?.close()
        let p = GlassPanel(size: CGSize(width: 460, height: 170)) {
            SaveSceneBox(onDone: { SaveSceneHotKey.panel?.close() })
        }
        panel = p
        p.present()
    }
}
