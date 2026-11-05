import AppKit
import SwiftUI
import WindowKit

/// Small glass toast at the bottom of the main display, optionally with an action
/// such as Undo or Skip.
@MainActor
final class Toast {
    static let shared = Toast()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = ToastModel()

    func show(_ text: String, detail: String? = nil, action: (title: String, run: () -> Void)? = nil,
              duration: TimeInterval = 4, progress: Bool = false) {
        model.text = text
        model.detail = detail
        model.actionTitle = action?.title
        model.action = action.map { a in { a.run(); Toast.shared.hide() } }
        model.showsProgress = progress
        let p = panel ?? makePanel()
        panel = p
        position(p)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }
        hideWork?.cancel()
        if duration > 0 {
            let work = DispatchWorkItem { MainActor.assumeIsolated { Toast.shared.hide() } }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { Toast.shared.panel?.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.appearance = NSAppearance(named: .aqua)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: ToastView(model: model))
        return p
    }

    private func position(_ p: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        let size = NSSize(width: 460, height: 64)
        p.setFrame(NSRect(x: v.midX - size.width / 2, y: v.minY + 28, width: size.width, height: size.height), display: true)
    }
}

@MainActor
final class ToastModel: ObservableObject {
    @Published var text = ""
    @Published var detail: String?
    @Published var actionTitle: String?
    @Published var showsProgress = false
    var action: (() -> Void)?
}

struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        HStack(spacing: 10) {
            if model.showsProgress {
                ProgressView().controlSize(.small).tint(Theme.spot)
            } else {
                Image(nsImage: Mark.image(size: 16))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if let d = model.detail {
                    Text(d).font(.system(size: 11)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
            }
            if let title = model.actionTitle {
                Button(title) { model.action?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.spot)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.spotSoft))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .background(Capsule().fill(Theme.glass))
        .overlay(Capsule().strokeBorder(Theme.line))
        .shadow(color: Color(hex: 0x7a4a2a, alpha: 0.18), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
    }
}
