import AppKit
import StageOneCore
import SwiftUI

/// SO-015: Settings › Rules › Apps Stage One leaves alone.
struct AppExceptionsCard: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        StageCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apps that float").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("Some apps won't let Stage One move their windows. Their windows float above the stage and stay visible with every group.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Menu("Add app") {
                    ForEach(addable, id: \.bundleID) { app in
                        Button(app.name) { add(app.bundleID, app.name) }
                    }
                    if addable.isEmpty { Text("No other apps are open") }
                }
                .fixedSize()
            }
            if prefs.appExceptions.isEmpty {
                Note(text: "No apps yet. Stage One adds an app here when it ignores a move.")
            } else {
                VStack(spacing: 0) {
                    ForEach(prefs.appExceptions) { e in row(e) }
                }
            }
        }
    }

    private func row(_ e: AppException) -> some View {
        HStack(spacing: 10) {
            if let icon = icon(for: e.bundleID) {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Theme.spotSoft).frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(Self.reason(e.reason)).font(.system(size: 11)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            Toggle("Float", isOn: binding(e.bundleID)).toggleStyle(.switch).controlSize(.small)
            Button {
                AppExceptionsService.update(prefs.appExceptions.filter { $0.bundleID != e.bundleID })
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink3)
            .help("Remove from the list")
        }
        .padding(.vertical, 6)
    }

    static func reason(_ r: AppException.Reason) -> String {
        switch r {
        case .knownList: return "Known not to cooperate"
        case .game: return "Game"
        case .detected: return "Ignored a move"
        case .user: return "Added by you"
        }
    }

    private func binding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { prefs.appExceptions.first { $0.bundleID == bundleID }?.floats ?? false },
            set: { on in
                var list = prefs.appExceptions
                if let i = list.firstIndex(where: { $0.bundleID == bundleID }) { list[i].floats = on }
                AppExceptionsService.update(list)
            })
    }

    private struct RunningApp { let bundleID: String; let name: String }

    private var addable: [RunningApp] {
        let listed = Set(prefs.appExceptions.map(\.bundleID))
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let b = app.bundleIdentifier, b != own, !listed.contains(b) else { return nil }
                return RunningApp(bundleID: b, name: app.localizedName ?? b)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ bundleID: String, _ name: String) {
        var list = prefs.appExceptions
        Uncooperative.flag(&list, bundleID: bundleID, name: name, reason: .user)
        AppExceptionsService.update(list)
    }

    private func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
