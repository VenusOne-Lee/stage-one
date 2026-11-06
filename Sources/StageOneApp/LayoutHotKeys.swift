import AppKit
import StageOneCore
import WindowKit

/// SO-042: ⌃⌥← → ↑ put the focused window in the left or right half or fill the stage;
/// ⌃⌥G arranges the stage in a grid. All four can be changed in Settings › Shortcuts.
@MainActor
final class LayoutHotKeys {
    static let shared = LayoutHotKeys()
    private var ids: [UInt32] = []

    func install() {
        uninstall()
        let overrides = Preferences.shared.layoutShortcuts
        for action in LayoutShortcut.allCases {
            let s = action.shortcut(in: overrides)
            if let id = HotKeys.shared.register(.init(keyCode: s.keyCode, modifiers: s.modifiers), action: {
                LayoutHotKeys.perform(action)
            }) { ids.append(id) }
        }
    }

    func uninstall() {
        ids.forEach { HotKeys.shared.unregister($0) }
        ids.removeAll()
    }

    static func perform(_ action: LayoutShortcut) {
        if action == .commandBar {
            Panels.shared.show(.commandBar)
            return
        }
        if action == .meetingMode {
            MeetingMode.shared.toggle()
            return
        }
        let c = StageController.shared
        guard c.isRunning else { return }
        if action == .grid {
            LayoutService.apply(.grid)
            return
        }
        guard let id = AX.focusedWindowID(), let w = c.inventory[id], !c.parking.isParked(id),
              let area = ScreenLayouts.layout(containing: w.frame)?.usableFrame else { return }
        let zone: SnapZone
        switch action {
        case .leftHalf: zone = .leftHalf
        case .rightHalf: zone = .rightHalf
        default: zone = .fill
        }
        c.mover.animate(w, to: zone.frame(in: area), duration: 0.3)
    }
}
