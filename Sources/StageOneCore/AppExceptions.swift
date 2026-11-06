import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// SO-015: apps Stage One doesn't move. Some apps ignore Accessibility moves (games, some
/// Electron and launcher apps); parking them fails and leaves their windows on stage.
/// Their windows float above the stage instead: never parked, visible with every group.
public struct AppException: Codable, Sendable, Equatable, Identifiable {
    public enum Reason: String, Codable, Sendable {
        /// On Stage One's tested list.
        case knownList
        /// A game (its App Store category).
        case game
        /// Stage One tried to move a window and the app put it back.
        case detected
        /// Added by the user in Settings.
        case user
    }

    public var bundleID: String
    public var name: String
    public var reason: Reason
    /// True: windows float above the stage. False: Stage One manages the app anyway.
    public var floats: Bool

    public var id: String { bundleID }

    public init(bundleID: String, name: String, reason: Reason, floats: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.reason = reason
        self.floats = floats
    }
}

public enum Uncooperative {
    /// Apps known to ignore or fight Accessibility moves.
    public static let known: [String: String] = [
        "com.valvesoftware.steam": "Steam",
        "com.epicgames.EpicGamesLauncher": "Epic Games Launcher",
        "com.apple.iphonesimulator": "Simulator",
    ]

    /// App Store categories for games (`LSApplicationCategoryType`).
    public static func isGame(category: String?) -> Bool {
        guard let c = category?.lowercased() else { return false }
        return c == "public.app-category.games" || c.hasPrefix("public.app-category.") && c.hasSuffix("-games")
    }

    /// True when a window ended up far from where it was sent, so the app ignored the move.
    /// The tolerance is generous: macOS itself nudges windows parked in a corner a little.
    public static func ignoredMove(target: CGPoint, actual: CGRect, tolerance: CGFloat = 200) -> Bool {
        abs(actual.minX - target.x) > tolerance || abs(actual.minY - target.y) > tolerance
    }

    /// Bundle ids whose windows float (not managed).
    public static func floating(_ list: [AppException]) -> Set<String> {
        Set(list.filter(\.floats).map(\.bundleID))
    }

    /// Flags an app unless it's already listed (a user's choice is never overridden).
    /// Returns true if it was added.
    @discardableResult
    public static func flag(_ list: inout [AppException], bundleID: String, name: String, reason: AppException.Reason) -> Bool {
        guard !list.contains(where: { $0.bundleID == bundleID }) else { return false }
        list.append(AppException(bundleID: bundleID, name: name, reason: reason))
        return true
    }
}
