import ApplicationServices
import CoreGraphics
import Foundation
import StageOneCore

/// Private but long-stable SPI: the CGWindowID behind an AXUIElement (also used by WindowKit).
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func axGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Reads Stage One's parked.json and moves each still-existing window back to its saved frame
/// with the Accessibility API. Runs without the app (and without AppKit) for crash recovery.
enum ParkedRestore {
    /// Mirrors `Parking.Record` / `Parking.Entry` in WindowKit (written with `IPC.encode`).
    struct Record: Codable {
        var snapshot: WindowSnapshot
        var frame: CGRect
    }

    struct Entry: Codable {
        var id: UInt32
        var record: Record
    }

    static var defaultFile: URL { IPC.supportDirectory.appendingPathComponent("parked.json") }

    /// Restores what it can. Entries whose window can't be found are written back so the next
    /// launch of the app can still reconcile them; the file is deleted once nothing is left.
    /// Returns a one-line summary (empty when there was nothing to do).
    @discardableResult
    static func restore(file: URL) -> String {
        guard let data = try? Data(contentsOf: file) else { return "" }
        guard let entries = try? IPC.decode([Entry].self, data) else {
            return "stage watchdog: could not read \(file.path)"
        }
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return ""
        }
        guard AXIsProcessTrusted() else {
            // Leave the file for the app's own recovery on next launch.
            return "stage watchdog: no Accessibility access; \(entries.count) parked window(s) left for Stage One"
        }

        var unresolved: [Entry] = []
        var restored = 0
        let byPID = Dictionary(grouping: entries, by: { $0.record.snapshot.pid })
        for (pid, group) in byPID {
            let windows = axWindows(of: pid)
            var used = Set<Int>()
            for entry in group {
                if let index = match(entry, in: windows, excluding: used) {
                    used.insert(index)
                    setFrame(windows[index].element, entry.record.frame)
                    restored += 1
                } else {
                    unresolved.append(entry)
                }
            }
        }

        if unresolved.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else if let data = try? IPC.encode(unresolved) {
            try? data.write(to: file, options: .atomic)
        }
        return "stage watchdog: restored \(restored) window(s), \(unresolved.count) not found"
    }

    // MARK: Accessibility

    struct AXWindow {
        var element: AXUIElement
        var id: CGWindowID?
        var title: String
    }

    static func axWindows(of pid: Int32) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.map { el in
            var id: CGWindowID = 0
            let hasID = axGetWindow(el, &id) == .success && id != 0
            var title: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &title)
            return AXWindow(element: el, id: hasID ? id : nil, title: (title as? String) ?? "")
        }
    }

    /// CGWindowID first; then the same title within the same process.
    static func match(_ entry: Entry, in windows: [AXWindow], excluding used: Set<Int>) -> Int? {
        if let i = windows.indices.first(where: { !used.contains($0) && windows[$0].id == entry.id }) { return i }
        let title = entry.record.snapshot.title
        guard !title.isEmpty else { return nil }
        return windows.indices.first(where: { !used.contains($0) && windows[$0].title == title })
    }

    /// Size, position, size: apps clamp a size that doesn't fit at the old position.
    static func setFrame(_ element: AXUIElement, _ frame: CGRect) {
        var size = frame.size
        var origin = frame.origin
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s) }
    }
}
