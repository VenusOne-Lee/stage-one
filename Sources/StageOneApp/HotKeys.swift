import AppKit
import Carbon.HIToolbox

/// Global hotkeys through Carbon's RegisterEventHotKey (no extra permission needed).
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    struct Combo: Equatable, Sendable {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x5354_4731 // "STG1"

    private init() {}

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard status == noErr else { return status }
            let id = hk.id
            MainActor.assumeIsolated { HotKeys.shared.fire(id) }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handler)
    }

    /// Registers a hotkey and returns its id (for unregistering).
    @discardableResult
    func register(_ combo: Combo, action: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        actions[id] = action
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id) }
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    // MARK: Key codes

    static let digitKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5),
        UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
    ]
    static let option = UInt32(optionKey)
    static let command = UInt32(cmdKey)
    static let shift = UInt32(shiftKey)
    static let control = UInt32(controlKey)
}

/// SO-021: ⌥1 to ⌥9 switch groups; holding ⌥ shows number badges on the strip.
@MainActor
final class GroupHotKeys {
    static let shared = GroupHotKeys()
    private var ids: [UInt32] = []
    private var monitors: [Any] = []

    func install() {
        uninstall()
        guard Preferences.shared.groupHotkeysEnabled else { return }
        for (i, code) in HotKeys.digitKeyCodes.enumerated() {
            if let id = HotKeys.shared.register(.init(keyCode: code, modifiers: HotKeys.option), action: {
                StageController.shared.switchTo(index: i)
            }) { ids.append(id) }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { e in
            let optionOnly = e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            MainActor.assumeIsolated { GroupHotKeys.optionChanged(optionOnly) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in
            let optionOnly = e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            MainActor.assumeIsolated { GroupHotKeys.optionChanged(optionOnly) }
            return e
        }) { monitors.append(l) }
    }

    static func optionChanged(_ down: Bool) {
        if StripManager.shared.model.showNumbers != down { StripManager.shared.model.showNumbers = down }
    }

    func uninstall() {
        ids.forEach { HotKeys.shared.unregister($0) }
        ids.removeAll()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
