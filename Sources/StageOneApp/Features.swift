import AppKit

/// Starts and stops the features that hang off the stage controller, so the
/// app delegate only has to start the controller.
@MainActor
enum Features {
    static func start() {
        GroupHotKeys.shared.install()
        DragToGroup.shared.install()
        StripPlacement.shared.install()
        LaneGuardService.shared.install()
        ReflowService.install()
        LayoutService.install()
        SnapService.shared.install()
        SaveSceneHotKey.install()
        SessionAutosave.install()
        SceneRelaunch.install()
        SceneEdited.install()
        LaneGuardService.shared.sweep(animated: false)
    }

    static func stop() {
        GroupHotKeys.shared.uninstall()
        DragToGroup.shared.uninstall()
        StripPlacement.shared.uninstall()
        LaneGuardService.shared.uninstall()
        LayoutService.uninstall()
        SnapService.shared.uninstall()
        SaveSceneHotKey.uninstall()
    }
}
