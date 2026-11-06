import AppKit
import SwiftUI
import StageOneCore
import WindowKit

/// The strip: stacked, tilted previews of each off-stage group (SO-020).
struct StripView: View {
    @ObservedObject var model: StripModel
    @ObservedObject var controller: StageController
    @ObservedObject var prefs: Preferences

    var body: some View {
        let groups = controller.desk.stripGroups
        let vertical = model.edge.isVertical
        Group {
            if vertical {
                VStack(spacing: model.size == .compact ? 10 : 14) { tiles(groups) ; Spacer(minLength: 0) }
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
            } else {
                HStack(spacing: 14) { tiles(groups) ; Spacer(minLength: 0) }
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "strip")
        .onPreferenceChange(TileFrameKey.self) { [model] frames in
            MainActor.assumeIsolated { model.tileFrames = frames }
        }
        .onPreferenceChange(NewSlotFrameKey.self) { [model] f in
            MainActor.assumeIsolated { model.newSlotFrame = f }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: groups.map(\.id))
    }

    @ViewBuilder
    private func tiles(_ groups: [StageGroup]) -> some View {
        ForEach(groups) { g in
            let index = (controller.desk.groups.firstIndex { $0.id == g.id } ?? 0) + 1
            Group {
                if model.size == .compact {
                    CompactTile(group: g, number: index, controller: controller, model: model)
                } else {
                    GroupTile(group: g, number: index, edge: model.edge, controller: controller, model: model)
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(key: TileFrameKey.self, value: [g.id: geo.frame(in: .named("strip"))])
            })
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
        NewGroupSlot(model: model)
    }
}

/// One group: a stack of up to three previews tilted toward the stage, with its label.
struct GroupTile: View {
    let group: StageGroup
    let number: Int
    let edge: ScreenEdge
    @ObservedObject var controller: StageController
    @ObservedObject var model: StripModel
    @State private var hover = false
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        let windows = controller.windows(of: group)
        VStack(spacing: 6) {
            ZStack {
                ForEach(Array(windows.prefix(3).enumerated().reversed()), id: \.element.id) { i, w in
                    WindowPreview(window: w, thumbnails: controller.thumbnails)
                        .frame(width: 150, height: 96)
                        .offset(x: CGFloat(i) * 7 * sideSign, y: CGFloat(i) * -5)
                        .scaleEffect(1 - CGFloat(i) * 0.06)
                }
                if windows.isEmpty {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.glass).frame(width: 150, height: 96)
                        .overlay(Text("Empty").font(.caption).foregroundStyle(Theme.ink3))
                }
            }
            .rotation3DEffect(.degrees(hover ? 14 : 24), axis: tiltAxis, anchor: tiltAnchor, perspective: 0.6)
            .offset(x: edge.isVertical ? (hover ? 5 * sideSign : 0) : 0, y: edge.isVertical ? 0 : (hover ? 5 * sideSign : 0))
            .overlay(alignment: .topLeading) {
                if model.showNumbers && number <= 9 { NumberBadge(number: number) }
            }
            .overlay(alignment: .bottomTrailing) {
                if controller.hasFullscreen(group) { FullscreenBadge() }
            }
            .overlay {
                if model.dropTarget == group.id {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.spot, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(-6)
                }
            }
            label(windows)
        }
        .frame(maxWidth: 180)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hover = h } }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) { controller.addToStage(group.id) } else { controller.switchTo(group.id) }
        }
        .contextMenu { GroupMenu(group: group, controller: controller, rename: { draft = group.name; renaming = true }) }
        .onDrag {
            model.reordering = group.id
            return NSItemProvider(object: group.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ReorderDrop(target: group.id, model: model, controller: controller))
        .help(group.name)
    }

    @ViewBuilder
    private func label(_ windows: [TrackedWindow]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(controller.appIcons(of: group).enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            if renaming {
                TextField("Group name", text: $draft, onCommit: {
                    controller.rename(group.id, to: draft)
                    renaming = false
                })
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: 120)
                .onExitCommand { renaming = false }
            } else {
                Text(group.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { draft = group.name; renaming = true }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Theme.glass))
    }

    /// +1 when the stage is to the right/bottom of the strip.
    private var sideSign: CGFloat { (edge == .left || edge == .top) ? 1 : -1 }
    private var tiltAxis: (x: CGFloat, y: CGFloat, z: CGFloat) { edge.isVertical ? (0, 1, 0) : (1, 0, 0) }
    private var tiltAnchor: UnitPoint {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

/// A window preview: the ScreenCaptureKit thumbnail, or an app icon tile without it.
struct WindowPreview: View {
    let window: TrackedWindow
    @ObservedObject var thumbnails: Thumbnails

    var body: some View {
        ZStack {
            if let img = thumbnails.image(for: window.id) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: 0xfffdfb), Color(hex: 0xf5f1ec)], startPoint: .top, endPoint: .bottom)
                if let icon = window.app?.icon {
                    Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
        .shadow(color: Color(hex: 0x7a4a2a, alpha: 0.18), radius: 8, y: 4)
    }
}

/// Compact rail tile (SO-034): app icons and a number badge.
struct CompactTile: View {
    let group: StageGroup
    let number: Int
    @ObservedObject var controller: StageController
    @ObservedObject var model: StripModel
    @State private var hover = false

    var body: some View {
        let icons = controller.appIcons(of: group)
        VStack(spacing: 2) {
            HStack(spacing: -6) {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, i in Image(nsImage: i).resizable().frame(width: 26, height: 26) }
            }
            if number <= 9 { Text("⌥\(number)").font(Theme.mono).foregroundStyle(Theme.ink3) }
        }
        .frame(width: 56, height: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(hover ? Theme.spotSoft : Theme.glass))
        .overlay(alignment: .topTrailing) {
            if controller.hasFullscreen(group) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Theme.spot))
                    .offset(x: 3, y: -3)
                    .help("Full screen")
            }
        }
        .overlay {
            if model.dropTarget == group.id {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.spot, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .onHover { hover = $0 }
        .onTapGesture { controller.switchTo(group.id) }
        .contextMenu { GroupMenu(group: group, controller: controller, rename: {}) }
        .help(group.name)
    }
}

/// SO-014: marks a group holding a native full screen window, which Stage One leaves alone.
struct FullscreenBadge: View {
    var body: some View {
        Text("Full screen")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.spot)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.spotSoft))
            .overlay(Capsule().strokeBorder(Theme.spot.opacity(0.35)))
            .offset(x: 4, y: 4)
    }
}

struct NumberBadge: View {
    let number: Int
    var body: some View {
        Text("⌥\(number)")
            .font(Theme.mono.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.spot))
            .offset(x: -4, y: -6)
    }
}

/// "+ New group" drop slot (SO-022).
struct NewGroupSlot: View {
    @ObservedObject var model: StripModel
    var body: some View {
        if model.dragging {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(model.dropOnNew ? Theme.spot : Theme.ink3, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: 150, height: 60)
                .overlay(Text("+ New group").font(.system(size: 12, weight: .semibold)).foregroundStyle(model.dropOnNew ? Theme.spot : Theme.ink2))
                .background(Theme.glass.clipShape(RoundedRectangle(cornerRadius: 10)))
                .background(GeometryReader { geo in
                    Color.clear.preference(key: NewSlotFrameKey.self, value: geo.frame(in: .named("strip")))
                })
        }
    }
}

/// Right-click menu (SO-023).
struct GroupMenu: View {
    let group: StageGroup
    let controller: StageController
    let rename: () -> Void

    var body: some View {
        Button("Show on stage") { controller.switchTo(group.id) }
        Button("Add to stage  ⌥-click") { controller.addToStage(group.id) }
        Divider()
        Button("Rename…", action: rename)
        Menu("Colour") {
            ForEach(GroupColor.palette, id: \.self) { hex in
                Button { controller.setColor(group.id, hex) } label: {
                    Label(GroupColorNames.name(hex), systemImage: group.color == hex ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        }
        if NSScreen.screens.count > 1 {
            Menu("Move to display") {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { i, screen in
                    Button(screen.localizedName) { controller.moveGroup(group.id, toDisplay: Displays.stableID(of: screen)) }
                }
            }
        }
        Divider()
        Button("Close group") { controller.closeGroup(group.id) }
    }
}

/// Drag a group onto another to reorder the strip (SO-023).
struct ReorderDrop: DropDelegate {
    let target: UUID
    let model: StripModel
    let controller: StageController

    func validateDrop(info: DropInfo) -> Bool { model.reordering != nil }

    func dropEntered(info: DropInfo) {
        guard let moving = model.reordering, moving != target,
              let from = controller.desk.groups.firstIndex(where: { $0.id == moving }),
              let to = controller.desk.groups.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            controller.reorder(from: from, to: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        model.reordering = nil
        return true
    }
}

enum GroupColorNames {
    static func name(_ hex: String) -> String {
        ["#ef6f2e": "Stage orange", "#3b63e0": "Blue", "#f2b33d": "Amber", "#e0503d": "Red",
         "#8a5cd6": "Violet", "#d6457f": "Pink", "#2f8fd8": "Sky", "#b9bcc7": "Slate"][hex] ?? hex
    }
}

struct TileFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct NewSlotFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
