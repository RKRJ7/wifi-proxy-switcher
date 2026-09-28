import Foundation
import CoreWLAN
import CoreLocation

// MARK: - WiFi Monitor

/// Detects the current Wi-Fi SSID and notifies observers on SSID change.
/// Uses CWWiFiClient for real-time notifications and CoreLocation for SSID access on macOS 14+.
final class WiFiMonitor: NSObject {

    static let shared = WiFiMonitor()

    /// Called on the main thread whenever the SSID changes (or nil = disconnected).
    var onSSIDChange: ((String?) -> Void)?

    private(set) var currentSSID: String?
    private var wifiClient: CWWiFiClient?
    private var locationManager: CLLocationManager?

    private override init() {
        super.init()
    }

    // MARK: - Start Monitoring

    func start() {
        setupLocationIfNeeded()
        setupCoreWLAN()
    }

    // MARK: - CoreWLAN

    private func setupCoreWLAN() {
        wifiClient = CWWiFiClient.shared()
        wifiClient?.delegate = self
        do {
            try wifiClient?.startMonitoringEvent(with: .ssidDidChange)
        } catch {
            print("[WiFiMonitor] Failed to start SSID monitoring: \(error)")
        }
        // Read initial SSID
        refreshCurrentSSID()
    }

    // MARK: - Location (needed on macOS 14+ to read SSID)

    private func setupLocationIfNeeded() {
        let mgr = CLLocationManager()
        mgr.delegate = self
        locationManager = mgr
        // Request "when in use" — sufficient for SSID reading; no location data is stored.
        if mgr.authorizationStatus == .notDetermined {
            mgr.requestWhenInUseAuthorization()
        }
    }

    // MARK: - SSID Reading

    func refreshCurrentSSID() {
        let ssid = readCurrentSSID()
        if ssid != currentSSID {
            currentSSID = ssid
            DispatchQueue.main.async {
                self.onSSIDChange?(ssid)
            }
        }
    }

    /// Reads the SSID of the currently associated Wi-Fi network.
    func readCurrentSSID() -> String? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        return iface.ssid()
    }
}

// MARK: - CWEventDelegate

extension WiFiMonitor: CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        refreshCurrentSSID()
    }

    func clientConnectionInterrupted() {
        // Attempt to re-register
        setupCoreWLAN()
    }

    func clientConnectionInvalidated() {
        setupCoreWLAN()
    }
}

// MARK: - CLLocationManagerDelegate

extension WiFiMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            refreshCurrentSSID()
        case .denied, .restricted:
            print("[WiFiMonitor] Location access denied — SSID may not be readable on macOS 14+.")
            // App still works; SSID may return nil.
        default:
            break
        }
    }
}
