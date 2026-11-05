import AppKit

/// Starts and stops the features that hang off the stage controller, so the
/// app delegate only has to start the controller.
@MainActor
enum Features {
    static func start() {
        GroupHotKeys.shared.install()
    }

    static func stop() {
        GroupHotKeys.shared.uninstall()
    }
}
