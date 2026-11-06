import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// SO-080: the command bar (⌃Space by default, changeable in Settings › Shortcuts).
/// Fuzzy search across groups, scenes, layouts, rewind points, rules and every window
/// title. ↑ ↓ move, Enter runs, Esc or clicking away closes.
@MainActor
enum CommandBar {
    private static var panel: CommandBarPanel?

    static func show() {
        if let p = panel, p.isVisible { p.close(); return }   // the hotkey toggles
        let p = CommandBarPanel {
            CommandBarView(items: CommandBar.items(), run: { item in
                CommandBar.panel?.close()
                CommandBar.run(item.action)
            }, close: { CommandBar.panel?.close() })
        }
        panel = p
        p.present()
    }

    /// Everything the bar can do right now, in the prototype's order.
    static func items(now: Date = Date()) -> [PaletteItem] {
        let c = StageController.shared
        var out: [PaletteItem] = []
        let groups = c.desk.groups
        for (i, g) in groups.enumerated() {
            out.append(PaletteItem(.group, g.name, hint: i < 9 ? "⌥\(i + 1)" : "", action: .switchGroup(g.id)))
        }
        let store = SceneStore.shared
        store.reload()
        for s in store.scenes {
            out.append(PaletteItem(.scene, "Restore \(s.name)", action: .restoreScene(s.name)))
        }
        out.append(PaletteItem(.scene, "Save this desk as a scene", hint: "⌘⇧S", action: .saveScene))
        for kind in [LayoutKind.halves, .focus, .thirds, .grid, .free] {
            out.append(PaletteItem(.arrange, "Arrange: \(kind.title)", action: .arrange(kind)))
        }
        out.append(PaletteItem(.time, "Rewind your desk", action: .openRewind))
        let rewind = RewindStore.shared
        rewind.reload()
        for snap in rewind.snapshots.suffix(8).reversed() {
            out.append(PaletteItem(.time, Palette.rewindTitle(snap.date, now: now),
                                   hint: snap.date.formatted(.relative(presentation: .named)), action: .rewind(snap.date)))
        }
        let meeting = LayoutShortcut.meetingMode.shortcut(in: Preferences.shared.layoutShortcuts).display
        out.append(PaletteItem(.share, MeetingMode.shared.on ? "Turn Meeting mode off" : "Turn Meeting mode on",
                               hint: meeting, action: .toggleMeetingMode))
        out.append(PaletteItem(.rules, "Edit rules", action: .openRules))
        for s in store.scenes {
            guard let r = s.rule, r.enabled else { continue }
            let when = RuleTrigger(rawValue: r.type)?.title ?? r.type
            out.append(PaletteItem(.rules, "\(when): \(s.name)", action: .openRules))
        }
        for g in groups {
            for id in g.windowIDs {
                guard let w = c.inventory[id] ?? c.inventory.fullscreen[id] else { continue }
                let title = w.title.isEmpty ? (w.app?.localizedName ?? "Window") : w.title
                out.append(PaletteItem(.window, title, hint: g.name, action: .focusWindow(id)))
            }
        }
        return out
    }

    static func run(_ action: PaletteItem.Action) {
        let c = StageController.shared
        switch action {
        case .switchGroup(let id):
            guard c.isRunning else { return }
            c.switchTo(id)
        case .restoreScene(let name):
            SceneStore.shared.reload()
            if let s = SceneStore.shared.scenes.first(where: { $0.name == name }) { SceneRestore.restore(s) }
        case .saveScene:
            Panels.shared.show(.saveScene)
        case .arrange(let kind):
            LayoutService.apply(kind)
        case .openRewind:
            Panels.shared.show(.rewind)
        case .rewind(let date):
            let store = RewindStore.shared
            if let snap = store.snapshots.first(where: { $0.date == date }), let scene = store.load(snap) {
                store.go(to: scene, at: date)
            }
        case .openRules:
            Panels.shared.show(.rules)
        case .toggleMeetingMode:
            MeetingMode.shared.toggle()
        case .focusWindow(let id):
            guard c.isRunning else { return }
            if let g = c.desk.groups.first(where: { $0.windowIDs.contains(id) }), g.id != c.desk.activeID {
                c.switchTo(g.id)
            }
            // Raise after the switch has unparked it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                MainActor.assumeIsolated {
                    guard let w = StageController.shared.inventory[id] ?? StageController.shared.inventory.fullscreen[id] else { return }
                    AX.raise(w.element)
                    w.app?.activate()
                }
            }
        }
    }
}

/// A borderless glass bar near the top of the screen that closes when it loses focus.
final class CommandBarPanel: NSPanel, NSWindowDelegate {
    static let width: CGFloat = 600

    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 420),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .modalPanel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
        let root = content()
            .frame(width: Self.width)
            .background(VisualEffect().ignoresSafeArea())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .environment(\.colorScheme, .light)
            // The window keeps its height; the bar grows down from the top and the rest is
            // transparent (and click-through).
            .frame(maxHeight: .infinity, alignment: .top)
        contentView = NSHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }

    func present() {
        // Top third of the screen with the mouse, like Spotlight.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            setFrameTopLeftPoint(NSPoint(x: f.midX - Self.width / 2, y: f.maxY - f.height * 0.18))
        }
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

struct CommandBarView: View {
    let items: [PaletteItem]
    var run: (PaletteItem) -> Void
    var close: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var shown: [PaletteItem] { Palette.filter(items, query: query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Switch group, restore a scene, arrange…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .focused($focused)
                .onChange(of: query) { selection = 0 }
                .onSubmit { if shown.indices.contains(selection) { run(shown[selection]) } }
                .onKeyPress(.downArrow) { selection = Palette.move(selection, by: 1, count: shown.count); return .handled }
                .onKeyPress(.upArrow) { selection = Palette.move(selection, by: -1, count: shown.count); return .handled }
                .onExitCommand(perform: close)
            Rectangle().fill(Theme.line).frame(height: 1)
            if shown.isEmpty {
                Text("No match").font(.system(size: 13.5)).foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.offset) { i, item in
                                row(item, on: i == selection)
                                    .id(i)
                                    .contentShape(Rectangle())
                                    .onTapGesture { run(item) }
                                    .onHover { if $0 { selection = i } }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { focused = true }
    }

    private func row(_ item: PaletteItem, on: Bool) -> some View {
        HStack(spacing: 10) {
            Text(item.kind.rawValue.uppercased())
                .font(.system(size: 10.5, weight: .medium))
                .kerning(0.6)
                .opacity(0.55)
                .frame(width: 60, alignment: .leading)
            Text(item.title).font(.system(size: 13.5)).lineLimit(1)
            Spacer(minLength: 8)
            if !item.hint.isEmpty {
                Text(item.hint).font(Theme.mono).opacity(0.6).lineLimit(1)
            }
        }
        .foregroundStyle(on ? Color.white : Theme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Theme.ink : Color.clear))
    }
}
