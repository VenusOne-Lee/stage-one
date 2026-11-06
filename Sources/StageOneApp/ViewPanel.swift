import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// SO-036: the View panel (menu bar › View). Strip and Dock on any edge, how windows treat
/// the strip, a mini schematic, a note, and Apple's way / Stage One way presets.
@MainActor
enum ViewPanel {
    private static var panel: GlassPanel?

    static func show() {
        if let p = panel, p.isVisible { p.makeKeyAndOrderFront(nil); return }
        let p = GlassPanel(size: CGSize(width: 440, height: 520)) {
            ViewPanelView(prefs: Preferences.shared, close: { ViewPanel.panel?.close() })
        }
        panel = p
        p.present()
    }
}

/// Moves the Dock. Same as System Settings › Desktop & Dock › Position on screen.
@MainActor
enum DockControl {
    static func set(_ edge: ScreenEdge) {
        guard edge != .top, edge != Displays.dockEdge else { return }
        run("/usr/bin/defaults", ["write", "com.apple.dock", "orientation", "-string", edge.rawValue])
        run("/usr/bin/killall", ["Dock"])
        // The Dock takes a moment to come back; then the strip re-places itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { MainActor.assumeIsolated { StripPlacement.shared.changed() } }
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); p.waitUntilExit() } catch { NSLog("Stage One: \(path) failed: \(error)") }
    }
}

struct ViewPanelView: View {
    @ObservedObject var prefs: Preferences
    var close: () -> Void
    /// Showing Apple's way: options Stage Manager lacks are greyed out.
    @State private var apple = false
    @State private var dock = Displays.dockEdge

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Strip & Dock").font(Theme.display(20)).foregroundStyle(Theme.ink)
                    Text("Put them on any edge. Pick how windows treat the strip.")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.ink3).help("Close")
            }
            row("Strip") {
                seg(key: "strip", selection: $prefs.stripEdge,
                    options: [(.left, "Left"), (.right, "Right"), (.top, "Top"), (.bottom, "Bottom")])
            }
            row("Dock") {
                seg(key: "dock", selection: Binding(get: { dock }, set: { dock = $0; DockControl.set($0) }),
                    options: [(.bottom, "Bottom"), (.left, "Left"), (.right, "Right")])
            }
            row("Windows") {
                seg(key: "mode", selection: $prefs.overlapMode,
                    options: [(.reserve, "Never overlap"), (.overlap, "Can overlap"), (.autohide, "Auto-hide")])
            }
            row("Size") {
                seg(key: "size", selection: $prefs.stripSize,
                    options: [(.full, "Previews"), (.compact, "Compact icons")])
            }
            HStack(alignment: .center, spacing: 16) {
                Schematic(drawing: ViewSchematic.drawing(strip: prefs.stripEdge, dock: dock,
                                                         mode: prefs.overlapMode, size: prefs.stripSize))
                    .frame(width: 200, height: 125)
                VStack(alignment: .leading, spacing: 6) {
                    legend(Theme.spot, "Strip")
                    legend(.white, "Dock", outline: true)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.focus, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: 12, height: 9)
                        Text("Window space").font(.system(size: 11)).foregroundStyle(Theme.ink2)
                    }
                }
            }
            note
            HStack(spacing: 8) {
                Spacer()
                Button("Show Apple's way") { applyApple() }
                    .buttonStyle(StageButtonStyle(kind: apple ? .spot : .ghost))
                Button("Stage One way") { applyStageOne() }
                    .buttonStyle(StageButtonStyle(kind: apple ? .ghost : .spot))
            }
        }
        .onAppear { dock = Displays.dockEdge }
    }

    private var note: some View {
        let text: AttributedString = apple
            ? (try? AttributedString(markdown: "**Apple's way.** The strip can only sit left or right, it jumps sides when the Dock moves, and it hides whenever a window touches it. Drag a window over it to see.")) ?? ""
            : (try? AttributedString(markdown: "**Stage One way.** Strip and Dock go on any edge, even the same one (the strip sits just inside the Dock). With Never overlap, windows and app sidebars always stay clear of the strip.")) ?? ""
        return Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.spotSoft.opacity(0.5)))
    }

    private func applyApple() {
        let p = ViewSchematic.applesWay(dock: dock)
        prefs.stripEdge = p.strip
        prefs.overlapMode = p.mode
        prefs.stripSize = p.size
        apple = true
    }

    private func applyStageOne() {
        let p = ViewSchematic.stageOneWay
        prefs.stripEdge = p.strip
        prefs.overlapMode = p.mode
        prefs.stripSize = p.size
        apple = false
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink2).frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// A segmented control drawn like the prototype's, with Apple-only greying.
    private func seg<V: Hashable & RawRepresentable>(key: String, selection: Binding<V>, options: [(V, String)]) -> some View
    where V.RawValue == String {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let title = options[i].1
                let on = selection.wrappedValue == value
                let allowed = !apple || ViewSchematic.isApple(allowed: key, value: value.rawValue, dock: dock)
                Button { selection.wrappedValue = value } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Theme.ink)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.spot : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!allowed)
                .opacity(allowed ? 1 : 0.35)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
    }

    private func legend(_ color: Color, _ title: String, outline: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 9)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(outline ? 0.3 : 0), lineWidth: 0.5))
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.ink2)
        }
    }
}

/// The mini schematic: a screen with the Dock, the strip and the dashed window space.
private struct Schematic: View {
    let drawing: ViewSchematic.Drawing

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / drawing.screen.width
            let r = { (rect: CGRect) in CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k) }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(hex: 0xf7e6d8), Color(hex: 0xefd2bd)], startPoint: .top, endPoint: .bottom))
                Rectangle().fill(Color.white.opacity(0.7)).frame(height: 25 * k)
                place(r(drawing.windowSpace.insetBy(dx: 6, dy: 6))) {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.focus, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                place(r(drawing.strip.insetBy(dx: 8, dy: 8))) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.spot.opacity(0.85))
                }
                place(r(drawing.dock.insetBy(dx: 6, dy: 8))) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: drawing)
        }
    }

    private func place<C: View>(_ rect: CGRect, @ViewBuilder _ content: () -> C) -> some View {
        content().frame(width: max(0, rect.width), height: max(0, rect.height)).offset(x: rect.minX, y: rect.minY)
    }
}
