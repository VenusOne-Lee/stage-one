import AppKit
import CoreLocation
import CoreWLAN
import StageOneCore

/// SO-074: posts `.wifi` rule events when the Mac joins a network. macOS only shares the
/// network name with apps that have Location access, so that is asked when a Wi-Fi rule is made.
@MainActor
final class WifiWatcher {
    static let shared = WifiWatcher()

    private let client = CWWiFiClient.shared()
    private let events = WifiEvents()
    private let location = CLLocationManager()
    private var last: String?
    private var monitoring = false

    /// The current network's name, or nil (not joined, or no Location access).
    var currentNetwork: String? { client.interface()?.ssid() }

    var locationAllowed: Bool {
        switch location.authorizationStatus {
        case .notDetermined, .denied, .restricted: return false
        default: return true
        }
    }

    var locationDenied: Bool {
        let s = location.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Asks for Location the first time a Wi-Fi rule is made.
    func requestAccess() {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
    }

    func install() {
        guard !monitoring else { return }
        last = currentNetwork
        client.delegate = events
        do {
            try client.startMonitoringEvent(with: .ssidDidChange)
            monitoring = true
        } catch {
            NSLog("Stage One: Wi-Fi monitoring failed: \(error)")
        }
    }

    func uninstall() {
        try? client.stopMonitoringAllEvents()
        monitoring = false
    }

    /// Called on a network change, and every minute by the rule clock in case an event was missed.
    func check() {
        let now = currentNetwork
        defer { last = now }
        guard let joined = WifiRules.joined(previous: last, current: now),
              WifiRules.needed(SceneStore.shared.scenes) else { return }
        RuleService.shared.post(.wifi(joined))
    }
}

/// CoreWLAN calls back on its own queue; hop to the main actor.
final class WifiEvents: NSObject, CWEventDelegate, @unchecked Sendable {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { MainActor.assumeIsolated { WifiWatcher.shared.check() } }
    }
}
