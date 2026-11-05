import AppKit
import SwiftUI

/// Small shared pieces for Stage One's own windows (onboarding, Settings).
/// Colours are literal hex values from the Theme tokens so the styles stay
/// usable outside the main actor.

/// The prototype's `.btn`, `.btn.spot` and `.btn.ghost`.
struct StageButtonStyle: ButtonStyle {
    enum Kind { case spot, ink, ghost }
    var kind: Kind = .spot

    func makeBody(configuration: Configuration) -> some View {
        StageButtonBody(configuration: configuration, kind: kind)
    }
}

private struct StageButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: StageButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(kind == .ghost ? Color(hex: 0x20222b) : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Rectangle())
    }

    private var background: Color {
        switch kind {
        case .spot: return Color(hex: 0xef6f2e)
        case .ink: return Color(hex: 0x20222b)
        case .ghost: return Color.black.opacity(0.06)
        }
    }
}

/// A rounded warm-white card, as used in the prototype's sheets.
struct StageCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(hex: 0x20222b, alpha: 0.10), lineWidth: 1)
            )
    }
}

/// "Allowed" / "Not allowed yet" pill. Granted is orange (never green).
struct PermissionPill: View {
    let granted: Bool
    var grantedText = "Allowed"
    var missingText = "Not allowed yet"

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? Color(hex: 0xef6f2e) : Color(hex: 0x8b8d98))
                .frame(width: 7, height: 7)
            Text(granted ? grantedText : missingText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(granted ? Color(hex: 0xb4501c) : Color(hex: 0x585b68))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(granted ? Color(hex: 0xfde3d2) : Color.black.opacity(0.06)))
        .animation(.easeOut(duration: 0.2), value: granted)
    }
}

/// The orange ring mark drawn in SwiftUI.
struct MarkView: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color(hex: 0xef6f2e), lineWidth: max(2, size * 0.14))
            Circle().fill(Color(hex: 0xef6f2e)).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
    }
}

/// A standard titled window for Stage One's own SwiftUI content, forced to light mode.
@MainActor
func makeStageWindow(title: String, size: NSSize, content: some View) -> NSWindow {
    let host = NSHostingController(rootView: AnyView(content.preferredColorScheme(.light)))
    let window = NSWindow(contentViewController: host)
    window.title = title
    window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = NSColor(srgbRed: 1, green: 253 / 255, blue: 251 / 255, alpha: 1)
    window.isReleasedWhenClosed = false
    window.setContentSize(size)
    window.center()
    return window
}
