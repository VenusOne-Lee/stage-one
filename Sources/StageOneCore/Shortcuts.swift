import Foundation

/// A key combination as Carbon's RegisterEventHotKey takes it. Pure so it can be tested
/// and stored; the modifier bits are Carbon's (cmdKey, shiftKey, optionKey, controlKey).
public struct Shortcut: Codable, Sendable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A global shortcut needs ⌃, ⌥ or ⌘, or it would swallow ordinary typing.
    public var isUsable: Bool { modifiers & (Self.command | Self.option | Self.control) != 0 }

    /// "⌃⌥←", in the order macOS menus use.
    public var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + KeyNames.name(keyCode)
    }
}

/// Names for ANSI virtual key codes (kVK_*).
public enum KeyNames {
    static let table: [UInt32: String] = {
        var t: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
            37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
            9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
        ]
        let fkeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fkeys.enumerated() { t[code] = "F\(i + 1)" }
        return t
    }()

    public static func name(_ keyCode: UInt32) -> String { table[keyCode] ?? "Key \(keyCode)" }
}

/// SO-042: the layout shortcuts, all customisable. SO-080 adds the command bar's, which
/// shares the storage and the conflict check.
public enum LayoutShortcut: String, Codable, Sendable, CaseIterable {
    case leftHalf, rightHalf, fill, grid, commandBar, meetingMode

    /// The window layout shortcuts (everything but the command bar and Meeting mode).
    public static var layouts: [LayoutShortcut] { allCases.filter { $0 != .commandBar && $0 != .meetingMode } }

    public var title: String {
        switch self {
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .fill: return "Fill the stage"
        case .grid: return "Grid"
        case .commandBar: return "Command bar"
        case .meetingMode: return "Meeting mode"
        }
    }

    /// ⌃⌥← → ↑ for halves and fill, ⌃⌥G for grid, ⌃Space for the command bar, ⌃⌥M for Meeting mode.
    public var defaultShortcut: Shortcut {
        let m = Shortcut.control | Shortcut.option
        switch self {
        case .leftHalf: return Shortcut(keyCode: 123, modifiers: m)
        case .rightHalf: return Shortcut(keyCode: 124, modifiers: m)
        case .fill: return Shortcut(keyCode: 126, modifiers: m)
        case .grid: return Shortcut(keyCode: 5, modifiers: m)
        // ⌘K clashes with many apps; ⌃Space is free unless several input sources are on.
        case .commandBar: return Shortcut(keyCode: 49, modifiers: Shortcut.control)
        // SO-110: ⌃⌥M (the prototype's ⌘⇧M is taken by Chrome and others).
        case .meetingMode: return Shortcut(keyCode: 46, modifiers: m)
        }
    }

    /// The shortcut in effect, given the user's overrides.
    public func shortcut(in overrides: [String: Shortcut]) -> Shortcut { overrides[rawValue] ?? defaultShortcut }

    /// Another action already using `shortcut`, if any.
    public static func conflict(for shortcut: Shortcut, except action: LayoutShortcut, overrides: [String: Shortcut]) -> LayoutShortcut? {
        allCases.first { $0 != action && $0.shortcut(in: overrides) == shortcut }
    }
}
