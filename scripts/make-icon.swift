// Draws the Stage One app icon and writes an .icns.
//   swift scripts/make-icon.swift Resources/AppIcon.icns
//
// Warm cream/peach rounded square (#fde3d2 -> #efe9e3) with the orange (#ef6f2e)
// ring-with-dot mark. Pure CoreGraphics + ImageIO, then `iconutil`. No Apple assets.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Renders the icon at `px` x `px` pixels. Geometry follows the macOS icon grid:
/// an 824/1024 rounded square centred on the canvas.
func render(px: Int) -> CGImage {
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0x20222b, 0.22))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0xefe9e3))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient body: peach at the top, warm cream at the bottom (CG origin is bottom-left).
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0xfde3d2), rgb(0xefe9e3)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY), options: [])
    ctx.restoreGState()

    // Hairline edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(0x20222b, 0.08))
    ctx.setLineWidth(max(1, s / 512))
    ctx.strokePath()

    // The mark: orange ring with a dot.
    let orange = rgb(0xef6f2e)
    let markD = body.width * 0.52
    let lw = markD * 0.11
    let ring = CGRect(x: body.midX - markD / 2, y: body.midY - markD / 2, width: markD, height: markD)
        .insetBy(dx: lw / 2, dy: lw / 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.012, color: rgb(0xef6f2e, 0.35))
    ctx.setStrokeColor(orange)
    ctx.setLineWidth(lw)
    ctx.strokeEllipse(in: ring)
    let dot = markD * 0.3
    ctx.setFillColor(orange)
    ctx.fillEllipse(in: CGRect(x: body.midX - dot / 2, y: body.midY - dot / 2, width: dot, height: dot))
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot finalize \(url.path)") }
}

let args = CommandLine.arguments
let output = URL(fileURLWithPath: args.count > 1 ? args[1] : "Resources/AppIcon.icns")
let fm = FileManager.default
let iconset = fm.temporaryDirectory
    .appendingPathComponent("StageOne-\(ProcessInfo.processInfo.processIdentifier)")
    .appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(render(px: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(px: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset.deletingLastPathComponent())
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed with status \(iconutil.terminationStatus)") }
print("Wrote \(output.path)")
