import AppKit
@preconcurrency import Sparkle

/// SO-133: in-app updates through Sparkle.
///
/// The feed is `SUFeedURL` in Info.plist (the appcast the release workflow attaches to the
/// latest GitHub release). Sparkle only starts when the bundle carries a real `SUPublicEDKey`
/// and runs from an `.app` bundle; dev builds (`swift run`) and builds without a key fall
/// back to opening the releases page, so a missing key never shows Sparkle's error alert.
///
///     UpdateChecker.shared.start()            // at launch: enables Sparkle's scheduled checks
///     UpdateChecker.shared.checkForUpdates()  // "Check for Updates…" menu item
@MainActor
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    static let releasesURL = URL(string: "https://github.com/VenusOne-Lee/stage-one/releases/latest")!

    private var controller: SPUStandardUpdaterController?

    private override init() { super.init() }

    /// True when this build can update itself through Sparkle.
    var isSparkleConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        guard Bundle.main.bundleURL.pathExtension == "app",
              let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String else { return false }
        // The placeholder in Resources/Info.plist is replaced by scripts/build-app.sh.
        return key.count >= 40 && !key.contains("__") && !key.uppercased().contains("PLACEHOLDER")
    }

    /// Starts the updater (scheduled background checks follow the user's Sparkle settings).
    /// Safe to call more than once.
    func start() {
        guard controller == nil, isSparkleConfigured else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Whether a "Check for Updates…" item should be enabled.
    var canCheckForUpdates: Bool {
        guard let controller else { return true }  // Fallback opens the releases page.
        return controller.updater.canCheckForUpdates
    }

    /// Shows Sparkle's update UI, or opens the GitHub releases page when Sparkle is not configured.
    func checkForUpdates() {
        start()
        if let controller {
            NSApp.activate()
            controller.checkForUpdates(nil)
        } else {
            NSWorkspace.shared.open(Self.releasesURL)
        }
    }
}
