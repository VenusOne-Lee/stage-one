import AppKit
import SwiftUI
import StageOneCore

/// SO-070: every scene rule with an on/off switch, and the last 50 runs.
@MainActor
enum RulesPanel {
    private static var panel: GlassPanel?

    static func show() {
        if let p = panel, p.isVisible { p.makeKeyAndOrderFront(nil); return }
        SceneStore.shared.reload()
        let p = GlassPanel(size: CGSize(width: 480, height: 560)) {
            RulesView(store: SceneStore.shared, service: RuleService.shared, close: { RulesPanel.panel?.close() })
        }
        panel = p
        p.present()
    }
}

struct RulesView: View {
    @ObservedObject var store: SceneStore
    @ObservedObject var service: RuleService
    var close: () -> Void

    var body: some View {
        let ruled = store.scenes.filter { $0.rule != nil }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(nsImage: Mark.image(size: 20))
                Text("Rules").font(Theme.display(22)).foregroundStyle(Theme.ink)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.ink3).help("Close")
            }
            Text("A rule restores a scene when something happens. Each run waits 5 seconds with a Skip button first.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            if ruled.isEmpty {
                Note(text: "No rules yet. Pick “Restore when…” as you save a scene (⌘⇧S).")
            } else {
                VStack(spacing: 6) {
                    ForEach(ruled) { scene in row(scene) }
                }
            }
            Text("Last runs").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
            if service.log.isEmpty {
                Text("Nothing has run yet.").font(.system(size: 12)).foregroundStyle(Theme.ink3)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(service.log.enumerated()), id: \.offset) { _, run in
                            HStack(spacing: 8) {
                                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.mono).foregroundStyle(Theme.ink3).frame(width: 130, alignment: .leading)
                                Text(run.scene).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer()
                                Text(Self.outcome(run.outcome)).font(.system(size: 11))
                                    .foregroundStyle(run.outcome == .ran ? Theme.spot : Theme.ink3)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 480, alignment: .top)
    }

    private func row(_ scene: StageScene) -> some View {
        let rule = scene.rule ?? StageScene.Rule(type: "")
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(Self.describe(rule)).font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { on in
                var s = scene
                s.rule?.enabled = on
                _ = try? store.write(s)
                store.reload()
            }))
            .labelsHidden().toggleStyle(.switch).tint(Theme.spot)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }

    static func describe(_ r: StageScene.Rule) -> String {
        guard let t = RuleTrigger(rawValue: r.type) else { return r.type }
        switch t {
        case .displayConnected: return "When \(r.display.map(RuleService.displayName) ?? "a display") connects"
        case .displayDisconnected: return "When a display unplugs"
        case .focus: return r.match.map { "When the \($0) Focus starts" } ?? "When a Focus starts"
        case .calendar: return r.match.map { "When “\($0)” starts" } ?? "When a calendar event starts"
        case .appLaunched: return "When \(r.app.map(RuleService.appName) ?? "an app") opens"
        case .wifi: return r.match.map { "When you join \($0)" } ?? "When you join a Wi-Fi network"
        case .time: return "Every day at \(r.time ?? "?")"
        }
    }

    static func outcome(_ o: RuleRun.Outcome) -> String {
        switch o {
        case .ran: return "Restored"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        }
    }
}
