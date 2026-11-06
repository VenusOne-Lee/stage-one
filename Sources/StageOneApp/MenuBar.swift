import AppKit
import StageOneCore
import WindowKit

/// SO-004: the orange ring in the menu bar and its menu. The menu is rebuilt each
/// time it opens, so the scene name, edited flag and pause state are always current.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Stage One"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        refreshIcon()
    }

    /// The ring is dimmed while Stage One is paused.
    func refreshIcon() {
        let paused = Preferences.shared.paused
        statusItem?.button?.image = Mark.image(size: 18, color: paused ? Theme.nsSpot.withAlphaComponent(0.4) : Theme.nsSpot)
        statusItem?.button?.toolTip = paused ? "Stage One (paused)" : "Stage One"
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = Preferences.shared

        menu.addItem(headerItem(prefs))
        menu.addItem(.separator())

        menu.addItem(item("Save scene…", #selector(saveScene), key: "s", modifiers: [.command, .shift]))
        menu.addItem(item("Scenes", #selector(scenes)))
        menu.addItem(item("Rewind", #selector(rewind)))
        menu.addItem(item("View", #selector(showView)))
        menu.addItem(item("Rules", #selector(rules)))
        menu.addItem(item("Command bar  \(LayoutShortcut.commandBar.shortcut(in: prefs.layoutShortcuts).display)", #selector(commandBar)))
        // SO-110.
        let meeting = item("Meeting mode  \(LayoutShortcut.meetingMode.shortcut(in: prefs.layoutShortcuts).display)", #selector(toggleMeeting))
        meeting.state = MeetingMode.shared.on ? .on : .off
        menu.addItem(meeting)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(settings), key: ","))
        let pause = item(prefs.paused ? "Resume Stage One" : "Pause Stage One", #selector(togglePause))
        menu.addItem(pause)
        // SO-135: Help › Send feedback.
        let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(item("Send feedback…", #selector(sendFeedback)))
        helpMenu.addItem(item("Stage One on GitHub", #selector(openGitHub)))
        help.submenu = helpMenu
        menu.addItem(help)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Stage One", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
    }

    /// First line: the scene on stage, with "· edited" once the desk has changed.
    private func headerItem(_ prefs: Preferences) -> NSMenuItem {
        let title: String
        if let scene = prefs.currentScene, !scene.isEmpty {
            title = prefs.sceneEdited ? "\(scene) · edited" : scene
        } else {
            title = "No scene yet"
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: prefs.paused ? "\(title) (paused)" : title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        header.image = Mark.image(size: 14)
        return header
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if !key.isEmpty { i.keyEquivalentModifierMask = modifiers }
        return i
    }

    // MARK: Actions

    @objc private func saveScene() { Panels.shared.show(.saveScene) }
    @objc private func scenes() { Panels.shared.show(.scenes) }
    @objc private func rewind() { Panels.shared.show(.rewind) }
    @objc private func showView() { Panels.shared.show(.view) }
    @objc private func rules() { Panels.shared.show(.rules) }
    @objc private func commandBar() { Panels.shared.show(.commandBar) }
    @objc private func toggleMeeting() { MeetingMode.shared.toggle() }
    @objc private func sendFeedback() { FeedbackService.send() }
    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/\(Feedback.repository)") { NSWorkspace.shared.open(url) }
    }

    @objc private func settings() { MenuBarController.openSettings() }

    static func openSettings() {
        SettingsWindow.shared.show(tab: .general)
    }

    @objc private func togglePause() {
        if Preferences.shared.paused { Engine.resume() } else { Engine.pause() }
        refreshIcon()
    }
}
