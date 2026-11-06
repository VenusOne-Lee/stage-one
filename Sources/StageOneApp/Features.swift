import AppKit

/// Starts and stops the features that hang off the stage controller, so the
/// app delegate only has to start the controller.
@MainActor
enum Features {
    static func start() {
        GroupHotKeys.shared.install()
        LayoutHotKeys.shared.install()
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
        AppExceptionsService.install()
        StripAutoHide.shared.install()
        RewindStore.shared.install()
        RuleService.shared.install()
        MeetingMode.shared.install()
        DisplayWatcher.install()
        CommandServer.shared.start()
        URLHandler.shared.install()
        LaneGuardService.shared.sweep(animated: false)
    }

    static func stop() {
        GroupHotKeys.shared.uninstall()
        LayoutHotKeys.shared.uninstall()
        DragToGroup.shared.uninstall()
        StripPlacement.shared.uninstall()
        LaneGuardService.shared.uninstall()
        LayoutService.uninstall()
        SnapService.shared.uninstall()
        SaveSceneHotKey.uninstall()
        CommandServer.shared.stop()
        StripAutoHide.shared.uninstall()
        RewindStore.shared.uninstall()
        RuleService.shared.uninstall()
        MeetingMode.shared.uninstall()
        DisplayWatcher.uninstall()
    }
}
