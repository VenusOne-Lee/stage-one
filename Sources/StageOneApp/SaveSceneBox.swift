import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// The Save box (⌘⇧S): name, trigger and options.
struct SaveSceneBox: View {
    var onDone: () -> Void = {}
    @State private var name = Scenes.suggestedName()
    @State private var trigger: SceneTrigger = .none
    @State private var triggerApp = ""
    @State private var triggerMatch = ""
    @State private var calendarDenied = false
    @State private var triggerTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var dnd = false
    @State private var meeting = false
    @State private var others: OtherApps = .leave
    @State private var wallpaper = false
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
                // SO-070: the trigger's parameter.
                if trigger == .appLaunched {
                    Picker("", selection: $triggerApp) {
                        Text("Any app").tag("")
                        ForEach(SceneTrigger.runningApps(), id: \.bundle) { Text($0.name).tag($0.bundle) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                } else if trigger == .calendar {
                    TextField("Title word or calendar", text: $triggerMatch)
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                        .help("Matches an event whose title contains this, or a calendar with this name. Empty matches any event.")
                } else if trigger == .time {
                    DatePicker("", selection: $triggerTime, displayedComponents: .hourAndMinute)
                        .labelsHidden().fixedSize()
                }
                Spacer()
                Toggle("Do Not Disturb", isOn: $dnd).toggleStyle(.checkbox).tint(Theme.spot)
                Toggle("Meeting mode", isOn: $meeting).toggleStyle(.checkbox).tint(Theme.spot)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink2)
            // SO-055: what else restoring does.
            HStack(spacing: 8) {
                Picker("Other apps", selection: $others) {
                    ForEach(OtherApps.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Toggle("Use this wallpaper", isOn: $wallpaper).toggleStyle(.checkbox).tint(Theme.spot)
                    .help("Restoring the scene sets the desktop picture you have now.")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink2)
            if calendarDenied {
                Text("Stage One can't see your calendar. Allow it in System Settings › Privacy & Security › Calendars.")
                    .font(.system(size: 11)).foregroundStyle(Theme.spot)
            }
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
        let picture = wallpaper ? NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path } : nil
        let options = StageScene.Options(dnd: dnd, meetingMode: meeting, hideOthers: others == .hide,
                                         closeOthers: others == .quit, wallpaper: picture)
        let rule = trigger.rule(app: triggerApp, time: triggerTime, match: triggerMatch)
        guard trigger == .calendar else {
            if Scenes.save(name: name, options: options, rule: rule) != nil { onDone() }
            return
        }
        // SO-073: calendar access is asked only when the first calendar rule is made.
        Task { @MainActor in
            guard await CalendarWatcher.shared.requestAccess() else { calendarDenied = true; return }
            if Scenes.save(name: name, options: options, rule: rule) != nil { onDone() }
        }
    }
}

/// SO-055: apps with no window in the scene.
enum OtherApps: String, CaseIterable {
    case leave, hide, quit

    var title: String {
        switch self {
        case .leave: return "Leave other apps"
        case .hide: return "Hide other apps"
        case .quit: return "Quit other apps (asks)"
        }
    }
}

/// Triggers offered in the Save box.
enum SceneTrigger: String, CaseIterable {
    case none, displayConnected, displayDisconnected, focus, calendar, appLaunched, time

    var title: String {
        switch self {
        case .none: return "Restore by hand"
        case .displayConnected: return "When this display connects"
        case .displayDisconnected: return "When a display unplugs"
        case .focus: return "When a Focus starts"
        case .calendar: return "When a calendar event starts"
        case .appLaunched: return "When an app opens"
        case .time: return "At a set time"
        }
    }

    /// The rule to save. "This display" is the newest one connected (an external, usually).
    @MainActor func rule(app: String, time: Date, match: String = "") -> StageScene.Rule? {
        switch self {
        case .none: return nil
        case .displayConnected:
            return .init(type: rawValue, display: NSScreen.screens.last.map(Displays.stableID(of:)))
        case .displayDisconnected: return .init(type: rawValue)
        case .appLaunched: return .init(type: rawValue, app: app.isEmpty ? nil : app)
        case .time:
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            return .init(type: rawValue, time: String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0))
        case .focus: return .init(type: rawValue)
        case .calendar:
            let m = match.trimmingCharacters(in: .whitespaces)
            return .init(type: rawValue, match: m.isEmpty ? nil : m)
        }
    }

    struct RunningApp { let bundle: String; let name: String }

    @MainActor static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { a in a.bundleIdentifier.map { RunningApp(bundle: $0, name: a.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
