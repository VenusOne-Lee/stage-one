import AppKit
import StageOneCore
import SwiftUI
import UniformTypeIdentifiers

/// SO-111: Settings › Privacy › what Meeting mode hides: whole apps, or single windows by title.
struct PrivateWindowsCard: View {
    @ObservedObject var prefs: Preferences
    @State private var pattern = ""
    @State private var patternApp = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Private apps").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Menu("Add app") {
                    ForEach(addable, id: \.bundleID) { app in
                        Button(app.name) { edit { $0.addApp(app.bundleID) } }
                    }
                    if !addable.isEmpty { Divider() }
                    Button("Choose…", action: chooseApp)
                }
                .fixedSize()
            }
            if prefs.privateList.apps.isEmpty {
                Note(text: "No private apps.")
            } else {
                VStack(spacing: 0) {
                    ForEach(prefs.privateList.apps, id: \.self) { b in
                        row(icon: Self.icon(b), title: Self.name(b), detail: nil) { edit { $0.removeApp(b) } }
                    }
                }
            }

            Divider().opacity(0.5)
            Text("Private windows").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
            Note(text: "Hide single windows whose title contains a word, like “Bank” or “Payroll”. Use * to match the whole title, like “* — Private”.")
            ForEach(prefs.privateList.titles, id: \.self) { r in
                row(icon: r.bundleID.flatMap(Self.icon), title: "“\(r.pattern)”",
                    detail: r.bundleID.map { "In \(Self.name($0))" } ?? "In any app") { edit { $0.removeTitle(r) } }
            }
            HStack(spacing: 8) {
                TextField("Title contains…", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPattern)
                Picker("", selection: $patternApp) {
                    Text("Any app").tag("")
                    ForEach(running, id: \.bundleID) { Text($0.name).tag($0.bundleID) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Button("Add", action: addPattern)
                    .buttonStyle(StageButtonStyle(kind: .ghost))
                    .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("Reset to Mail, Messages, Slack and WhatsApp") { prefs.privateList = PrivateList() }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
            }
        }
    }

    private func row(icon: NSImage?, title: String, detail: String?, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Theme.spotSoft).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Theme.ink3) }
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink3)
            .help("Remove")
        }
        .padding(.vertical, 5)
    }

    private func edit(_ change: (inout PrivateList) -> Void) {
        var l = prefs.privateList
        change(&l)
        prefs.privateList = l
    }

    private func addPattern() {
        edit { _ = $0.addTitle(pattern, bundleID: patternApp) }
        pattern = ""
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Make private"
        guard panel.runModal() == .OK, let url = panel.url,
              let b = Bundle(url: url)?.bundleIdentifier else { return }
        edit { $0.addApp(b) }
    }

    private struct RunningApp { let bundleID: String; let name: String }

    private var running: [RunningApp] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { a -> RunningApp? in
                guard let b = a.bundleIdentifier, b != own else { return nil }
                return RunningApp(bundleID: b, name: a.localizedName ?? b)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var addable: [RunningApp] {
        let listed = Set(prefs.privateList.apps)
        return running.filter { !listed.contains($0.bundleID) }
    }

    static func name(_ bundle: String) -> String { MeetingMode.appName(bundle) ?? bundle }

    static func icon(_ bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
