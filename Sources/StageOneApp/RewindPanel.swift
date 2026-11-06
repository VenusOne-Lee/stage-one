import AppKit
import SwiftUI
import StageOneCore

/// SO-061: drag back in time through the automatic snapshots.
@MainActor
enum RewindPanel {
    private static var panel: GlassPanel?

    static func show() {
        if let p = panel, p.isVisible { p.makeKeyAndOrderFront(nil); return }
        RewindStore.shared.take()   // so "now" is the latest point on the slider
        let p = GlassPanel(size: CGSize(width: 480, height: 600)) {
            RewindView(store: RewindStore.shared, close: { RewindPanel.panel?.close() })
        }
        panel = p
        p.present()
    }

    static func close() { panel?.close() }
}

struct RewindView: View {
    @ObservedObject var store: RewindStore
    var close: () -> Void
    @State private var index: Double = 0
    @State private var now = StageScene(name: "Now", displays: [], groups: [], active: 0)

    var body: some View {
        let snaps = store.snapshots
        let i = snaps.isEmpty ? 0 : min(snaps.count - 1, max(0, Int(index.rounded())))
        let isNow = snaps.isEmpty || i == snaps.count - 1
        let scene = snaps.isEmpty ? now : (store.load(snaps[i]) ?? now)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(nsImage: Mark.image(size: 20))
                Text("Rewind").font(Theme.display(22)).foregroundStyle(Theme.ink)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.ink3).help("Close")
            }
            Text("Stage One keeps a snapshot of your whole desk every 15 minutes for 7 days. Drag back in time to find a lost window.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            MiniDesk(scene: scene).frame(height: 170)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNow ? "Now" : label(snaps[i].date)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("\(isNow ? "The desk as it is" : snaps[i].date.formatted(.relative(presentation: .named))) · \(scene.groups.filter { !$0.windows.isEmpty }.count) groups, \(scene.windowCount) windows")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                }
                Spacer()
                if !isNow {
                    Button("Go back to this") {
                        store.go(to: scene, at: snaps[i].date)
                        close()
                    }
                    .buttonStyle(StageButtonStyle(kind: .spot))
                }
            }
            if snaps.count > 1 {
                VStack(spacing: 4) {
                    Slider(value: $index, in: 0...Double(snaps.count - 1), step: 1)
                        .tint(Theme.spot)
                    ticks(snaps)
                }
            } else {
                Note(text: "The first snapshots appear over the next 15 minutes.")
            }
            if !isNow { SinceThen(diff: SnapshotDiff.between(then: scene, now: now)) }
            // SO-062: bring back one window that existed then.
            Text("Bring back one thing").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
            if isNow {
                Text("Drag the slider left to compare.").font(.system(size: 12)).foregroundStyle(Theme.ink3)
            } else {
                BringBackList(gone: SnapshotDiff.between(then: scene, now: now).gone, scene: scene)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 520, alignment: .top)
        .onAppear {
            now = Scenes.capture(name: "Now")
            index = Double(max(0, store.snapshots.count - 1))
        }
    }

    /// Up to six evenly spaced time labels under the slider.
    private func ticks(_ snaps: [RewindStore.Snapshot]) -> some View {
        let n = min(6, snaps.count)
        let picks = (0..<n).map { k in snaps[n == 1 ? 0 : k * (snaps.count - 1) / (n - 1)] }
        return HStack {
            ForEach(Array(picks.enumerated()), id: \.offset) { k, s in
                if k > 0 { Spacer(minLength: 0) }
                Text(k == n - 1 ? "Now" : short(s.date)).font(.system(size: 10)).foregroundStyle(Theme.ink3)
            }
        }
    }

    private func label(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "Today \(d.formatted(date: .omitted, time: .shortened))"
            : Calendar.current.isDateInYesterday(d) ? "Yesterday \(d.formatted(date: .omitted, time: .shortened))"
            : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func short(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// SO-062: windows that existed then but are gone now, each with "Bring back".
struct BringBackList: View {
    let gone: [SnapshotDiff.Gone]
    let scene: StageScene
    @State private var asked: Set<String> = []

    var body: some View {
        if gone.isEmpty {
            Text("Nothing missing from now.").font(.system(size: 12)).foregroundStyle(Theme.ink3)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(gone.enumerated()), id: \.offset) { _, g in
                        let key = g.window.bundleId + g.window.title
                        HStack(spacing: 10) {
                            icon(g.window.bundleId)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.window.title.isEmpty ? (g.window.appName ?? g.window.bundleId) : g.window.title)
                                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text("was in \(g.group)").font(.system(size: 11)).foregroundStyle(Theme.ink3)
                            }
                            Spacer()
                            Button(asked.contains(key) ? "Opening…" : "Bring back") {
                                asked.insert(key)
                                SceneRelaunch.bringBack(g, from: scene)
                            }
                            .buttonStyle(StageButtonStyle(kind: .ghost))
                            .disabled(asked.contains(key))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.7)))
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    @ViewBuilder
    private func icon(_ bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Theme.spotSoft).frame(width: 24, height: 24)
        }
    }
}

/// "Since then": + windows opened since, − windows gone.
struct SinceThen: View {
    let diff: SnapshotDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Since then").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
            if diff.isEmpty {
                Text("Same windows, moved around.").font(.system(size: 12)).foregroundStyle(Theme.ink3)
            }
            ForEach(Array(diff.added.prefix(4).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 6) {
                    Text("+").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.focus)
                    Text(t).font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
            }
            ForEach(Array(diff.gone.prefix(4).enumerated()), id: \.offset) { _, g in
                HStack(spacing: 6) {
                    Text("−").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.danger)
                    Text(g.window.title.isEmpty ? (g.window.appName ?? g.window.bundleId) : g.window.title)
                        .font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
    }
}
