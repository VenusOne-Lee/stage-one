import AppKit
import SwiftUI

/// Design tokens from the prototype. Light mode only; no greens anywhere.
@MainActor
enum Theme {
    static let spot = Color(hex: 0xef6f2e)
    static let spotSoft = Color(hex: 0xfde3d2)
    static let ink = Color(hex: 0x20222b)
    static let ink2 = Color(hex: 0x585b68)
    static let ink3 = Color(hex: 0x8b8d98)
    static let focus = Color(hex: 0x3b63e0)
    static let danger = Color(hex: 0xe0503d)
    static let amber = Color(hex: 0xf2b33d)
    static let page = Color(hex: 0xefe9e3)
    static let glass = Color(red: 1, green: 252 / 255, blue: 249 / 255).opacity(0.72)
    static let line = Color(hex: 0x20222b).opacity(0.10)

    static let nsSpot = NSColor(srgbRed: 0xef / 255, green: 0x6f / 255, blue: 0x2e / 255, alpha: 1)

    static let mono = Font.custom("JetBrains Mono", size: 11).monospaced()
    /// Bricolage Grotesque when installed, otherwise a rounded bold system face.
    static func display(_ size: CGFloat) -> Font {
        NSFont(name: "BricolageGrotesque-Bold", size: size) != nil
            ? Font.custom("BricolageGrotesque-Bold", size: size)
            : Font.system(size: size, weight: .bold, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }

    init(hexString: String) {
        self.init(hex: UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xef6f2e)
    }
}

/// The Stage One mark: an orange ring with a dot.
@MainActor
enum Mark {
    static func image(size: CGFloat, color: NSColor = Theme.nsSpot) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lw = max(1.5, rect.width * 0.11)
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: lw / 2 + 1, dy: lw / 2 + 1))
            ring.lineWidth = lw
            color.setStroke()
            ring.stroke()
            let d = rect.width * 0.3
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
