import CoreLocation
import CoreWLAN

/// Current and saved Wi-Fi network names. macOS only reveals SSIDs to apps with Location access.
@MainActor
final class WiFi: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WiFi()

    private let manager = CLLocationManager()
    @Published private(set) var authorized = false
    @Published private(set) var undetermined = true

    override private init() {
        super.init()
        manager.delegate = self
        updateStatus()
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    var currentSSID: String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    /// Networks this Mac has joined before, so rules can be set up while away from them.
    var savedNetworks: [String] {
        let profiles = CWWiFiClient.shared().interface()?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return profiles.compactMap(\.ssid)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.updateStatus() }
    }

    private func updateStatus() {
        let status = manager.authorizationStatus
        authorized = status == .authorizedAlways || status == .authorized
        undetermined = status == .notDetermined
    }
}
