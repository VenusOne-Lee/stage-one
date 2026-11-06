import AppKit
import ServiceManagement
import StageOneCore
import SwiftUI
import WindowKit

/// SO-132: the Settings window. An AppKit window hosting SwiftUI (no SwiftUI `Settings` scene,
/// because the app uses the AppKit lifecycle). Open it with `SettingsWindow.shared.show(tab:)`.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, stripDock, shortcuts, rules, privacy, integrations, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .stripDock: return "Strip & Dock"
        case .shortcuts: return "Shortcuts"
        case .rules: return "Rules"
        case .privacy: return "Privacy"
        case .integrations: return "Integrations"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .stripDock: return "sidebar.left"
        case .shortcuts: return "keyboard"
        case .rules: return "wand.and.stars"
        case .privacy: return "hand.raised"
        case .integrations: return "puzzlepiece.extension"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let model = SettingsModel()

    func show(tab: SettingsTab = .general) {
        model.tab = tab
        if window == nil {
            let w = makeStageWindow(title: "Stage One Settings", size: NSSize(width: 780, height: 560),
                                    content: SettingsView(model: model, prefs: Preferences.shared))
            w.delegate = self
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Shell

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.tab.title)
                        .font(Theme.display(26))
                        .tracking(-0.5)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 780, height: 560)
        .background(Color(hex: 0xfffdfb))
        .foregroundStyle(Theme.ink)
        .tint(Theme.spot)
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .general: GeneralPane(prefs: prefs)
        case .stripDock: StripDockPane(prefs: prefs)
        case .shortcuts: ShortcutsPane(prefs: prefs)
        case .rules: RulesPane()
        case .privacy: PrivacyPane()
        case .integrations: IntegrationsPane()
        case .about: AboutPane()
        }
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                MarkView(size: 18)
                Text("Stage One").font(Theme.display(15))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
            ForEach(SettingsTab.allCases) { tab in
                SidebarRow(tab: tab, selected: model.tab == tab) { model.tab = tab }
            }
            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 10)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(Color(hex: 0xf5f1ec))
    }
}

private struct SidebarRow: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.spot : Theme.ink2)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.spotSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Building blocks

private struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

private struct Note: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var prefs: Preferences
    @State private var loginError: String?
    @State private var launchOn = false
    @State private var stageManagerOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StageCard {
                SettingRow(title: "Launch at login", detail: "Start Stage One when you log in to your Mac.") {
                    Toggle("", isOn: $launchOn).labelsHidden().toggleStyle(.switch)
                }
                if let loginError {
                    Text(loginError).font(.system(size: 12)).foregroundStyle(Theme.danger)
                }
            }
            StageCard {
                SettingRow(title: "Apple's Stage Manager",
                           detail: "Keep it off. Stage Manager and Stage One both hide and move windows, so they fight when both are on.") {
                    Toggle("", isOn: $stageManagerOn).labelsHidden().toggleStyle(.switch)
                }
                if stageManagerOn {
                    Text("Stage Manager is on. Windows may jump between it and Stage One.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                } else if prefs.stageManagerTurnedOff {
                    Note(text: "Stage One turned it off during setup. Switch it on here to undo that.")
                }
            }
            StageCard {
                SettingRow(title: "Spaces", detail: spacesDetail) {
                    Picker("", selection: $prefs.spacesMode) {
                        Text("Same groups").tag(SpacesMode.shared)
                        Text("Groups per Space").tag(SpacesMode.perSpace)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .disabled(!Spaces.isAvailable)
                }
            }
            StageCard {
                SettingRow(title: "Setup", detail: "Walk through permissions and Stage Manager again.") {
                    Button("Run setup again") { OnboardingWindow.shared.show() }
                        .buttonStyle(StageButtonStyle(kind: .ghost))
                }
            }
        }
        .onChange(of: prefs.spacesMode) { _, _ in StageController.shared.spacesModeChanged() }
        .onAppear {
            stageManagerOn = AppleStageManager.isOn
            let enabled = SMAppService.mainApp.status == .enabled
            if prefs.launchAtLogin != enabled { prefs.launchAtLogin = enabled }
            launchOn = enabled
        }
        .onChange(of: launchOn) { _, on in setLaunchAtLogin(on) }
        .onChange(of: stageManagerOn) { _, on in setStageManager(on) }
    }

    /// Both setters are no-ops when the system already matches, so syncing the toggles in onAppear is safe.
    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        guard on != (service.status == .enabled) else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        let enabled = service.status == .enabled
        prefs.launchAtLogin = enabled
        if launchOn != enabled { launchOn = enabled }
    }

    private func setStageManager(_ on: Bool) {
        guard on != AppleStageManager.isOn else { return }
        AppleStageManager.setEnabled(on)
        let now = AppleStageManager.isOn
        prefs.stageManagerTurnedOff = !now
        if stageManagerOn != now { stageManagerOn = now }
    }

    private var spacesDetail: String {
        guard Spaces.isAvailable else { return "This version of macOS doesn't let Stage One tell Spaces apart." }
        switch prefs.spacesMode {
        case .shared: return "Every Space shows the same groups. Full screen windows are left alone."
        case .perSpace: return "Each Space keeps its own groups and its own stage. Full screen windows are left alone."
        }
    }
}

// MARK: - Strip & Dock

private struct StripDockPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StageCard {
                SettingRow(title: "Strip edge", detail: "Put the strip on any edge, even the Dock's.") {
                    Picker("", selection: $prefs.stripEdge) {
                        ForEach(ScreenEdge.allCases, id: \.self) { e in Text(e.rawValue.capitalized).tag(e) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }
            StageCard {
                SettingRow(title: "Windows", detail: overlapDetail) {
                    Picker("", selection: $prefs.overlapMode) {
                        ForEach(OverlapMode.allCases, id: \.self) { m in Text(Self.title(of: m)).tag(m) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
            }
            StageCard {
                SettingRow(title: "Size", detail: "Previews show stacked windows; compact icons take a thin rail.") {
                    Picker("", selection: $prefs.stripSize) {
                        Text("Previews").tag(StripSize.full)
                        Text("Compact icons").tag(StripSize.compact)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            StageCard {
                SettingRow(title: "Live previews",
                           detail: Permissions.screenRecording
                               ? "Show small live previews of each group."
                               : "Needs Screen Recording access. Without it the strip shows app icons.") {
                    Toggle("", isOn: $prefs.livePreviews).labelsHidden().toggleStyle(.switch)
                }
                if !Permissions.screenRecording {
                    Button("Allow Screen Recording") {
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                    .buttonStyle(StageButtonStyle(kind: .ghost))
                }
            }
        }
        .onChange(of: prefs.stripEdge) { _, _ in StripManager.shared.layout() }
        .onChange(of: prefs.overlapMode) { _, _ in StripManager.shared.layout() }
        .onChange(of: prefs.stripSize) { _, _ in StripManager.shared.layout() }
        .onChange(of: prefs.livePreviews) { _, _ in StripManager.shared.layout() }
    }

    private var overlapDetail: String {
        switch prefs.overlapMode {
        case .reserve: return "Windows never slide under the strip, like the Dock."
        case .overlap: return "Apple's way: windows can cover the strip, which then hides."
        case .autohide: return "The strip stays hidden until the pointer reaches its edge."
        }
    }

    static func title(of mode: OverlapMode) -> String {
        switch mode {
        case .reserve: return "Never overlap"
        case .overlap: return "Can overlap"
        case .autohide: return "Auto-hide"
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var prefs: Preferences

    private static let rows: [(keys: String, action: String)] = [
        ("⌥1 – ⌥9", "Switch to group 1 to 9"),
        ("⌘⇧S", "Save scene"),
        ("⌃⌥←", "Left half"),
        ("⌃⌥→", "Right half"),
        ("⌃⌥↑", "Fill the stage"),
        ("⌃⌥G", "Grid"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StageCard {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().opacity(0.5) }
                    HStack {
                        Text(row.action).font(.system(size: 13.5))
                        Spacer()
                        KeyCap(text: row.keys)
                    }
                }
            }
            Toggle("Group hotkeys (⌥1 – ⌥9)", isOn: $prefs.groupHotkeysEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 13))
            Note(text: "Custom shortcuts are coming in a later version.")
        }
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.06)))
    }
}

// MARK: - Rules

private struct RulesPane: View {
    var body: some View {
        StageCard {
            Text("Rules restore a scene when a monitor connects, a Focus starts, a calendar event begins, an app opens or you join a Wi-Fi network.")
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
            Note(text: "Coming soon. Rules will be managed here and from the Rules panel.")
            Button("Open Rules") { Panels.shared.show(.rules) }
                .buttonStyle(StageButtonStyle(kind: .ghost))
        }
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StageCard {
                PrivacyLine(title: "No analytics", text: "Stage One collects nothing and sends nothing. There is no tracking and no account.")
                PrivacyLine(title: "Titles stay on your Mac", text: "Window titles, file names and previews are only used on this Mac and are never uploaded.")
                PrivacyLine(title: "Open source", text: "Every line is on GitHub, so anyone can check.")
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                StageCard {
                    PermissionRow(title: "Accessibility", detail: "Needed to move, resize and hide windows.",
                                  granted: Permissions.accessibility) {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    Divider().opacity(0.5)
                    PermissionRow(title: "Screen Recording", detail: "Optional. Used only for live previews in the strip.",
                                  granted: Permissions.screenRecording) {
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                }
            }
        }
    }
}

private struct PrivacyLine: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail) {
            HStack(spacing: 8) {
                PermissionPill(granted: granted)
                if !granted {
                    Button("Open Settings", action: open).buttonStyle(StageButtonStyle(kind: .ghost))
                }
            }
        }
    }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StageCard {
                CommandLineRow()
                Divider().opacity(0.5)
                IntegrationRow(title: "Alfred", detail: "A workflow with the keyword st for scenes, groups and layouts.")
                Divider().opacity(0.5)
                IntegrationRow(title: "Raycast", detail: "An extension with the same commands.")
                Divider().opacity(0.5)
                IntegrationRow(title: "Spotlight and Shortcuts", detail: "Every scene, group and layout as an App Intent.")
            }
            Note(text: "Installers for these arrive in upcoming versions.")
        }
    }
}

/// SO-100: links the bundled `stage` tool into /usr/local/bin.
private struct CommandLineRow: View {
    @State private var installed = CLIInstaller.isInstalled

    var body: some View {
        SettingRow(title: "Command line", detail: "The `stage` tool lists groups, restores scenes and arranges windows from Terminal.") {
            if installed {
                Text("Installed")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.spot)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.spotSoft))
            } else {
                Button("Install") { installed = CLIInstaller.install() }
                    .buttonStyle(StageButtonStyle(kind: .spot))
            }
        }
    }
}

private struct IntegrationRow: View {
    let title: String
    let detail: String

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Text("Coming soon")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.06)))
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    private static let comparison: [(need: String, apple: String, ours: String)] = [
        ("Come back to a whole setup", "Lost on restart or logout", "Scenes save every group, window, size and position"),
        ("Arrange windows neatly", "Free placement only", "Halves, thirds, main + side and grid"),
        ("Find the right group fast", "Up to about 6 unnamed groups", "Unlimited named groups, ⌥1 to ⌥9"),
        ("Strip and Dock where you want", "Strip covers app sidebars", "Any edge, and windows never slide under it"),
    ]

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let b, !b.isEmpty, b != v { return "Version \(v) (\(b))" }
        return "Version \(v)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                MarkView(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stage One").font(Theme.display(28)).tracking(-0.6)
                    Text(version).font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
                }
            }
            Text("Stage Manager's calm look, with the memory it never had. Free and open source under the MIT licence.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/VenusOne-Lee/stage-one")!) {
                    Text("View on GitHub")
                }
                .buttonStyle(StageButtonStyle(kind: .spot))
                Text("MIT licence").font(.system(size: 12)).foregroundStyle(Theme.ink3)
            }
            StageCard {
                ComparisonHeader()
                ForEach(Array(Self.comparison.enumerated()), id: \.offset) { _, row in
                    Divider().opacity(0.5)
                    ComparisonRow(need: row.need, apple: row.apple, ours: row.ours)
                }
            }
        }
    }
}

private struct ComparisonHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cell("What you need")
            cell("Stage Manager")
            cell("Stage One")
        }
    }

    private func cell(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComparisonRow: View {
    let need: String
    let apple: String
    let ours: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(need).font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(apple).font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ours).font(.system(size: 12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
