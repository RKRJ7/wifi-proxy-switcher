import Foundation

// MARK: - Data Model

/// Per-SSID proxy profile stored persistently via UserDefaults.
struct NetworkProfile: Codable {
    var ssid: String
    var proxyEnabled: Bool
    var httpHost: String
    var httpPort: Int
    var httpsHost: String
    var httpsPort: Int
    var useSameForHTTPS: Bool

    init(ssid: String,
         proxyEnabled: Bool = false,
         httpHost: String = "",
         httpPort: Int = 8080,
         httpsHost: String = "",
         httpsPort: Int = 8080,
         useSameForHTTPS: Bool = true)
    {
        self.ssid = ssid
        self.proxyEnabled = proxyEnabled
        self.httpHost = httpHost
        self.httpPort = httpPort
        self.httpsHost = useSameForHTTPS ? httpHost : httpsHost
        self.httpsPort = useSameForHTTPS ? httpPort : httpsPort
        self.useSameForHTTPS = useSameForHTTPS
    }

    /// Effective HTTPS host, respecting the "use same" flag.
    var effectiveHTTPSHost: String { useSameForHTTPS ? httpHost : httpsHost }
    /// Effective HTTPS port.
    var effectiveHTTPSPort: Int    { useSameForHTTPS ? httpPort : httpsPort }
}

// MARK: - Profile Store

/// Thread-safe persistent store for per-SSID NetworkProfiles.
final class ProfileStore {

    static let shared = ProfileStore()
    private let defaults = UserDefaults.standard
    private let key = "WiFiProxyProfiles_v1"
    private var cache: [String: NetworkProfile] = [:]
    private let queue = DispatchQueue(label: "com.proxytoggle.profilestore", attributes: .concurrent)

    private init() {
        loadFromDisk()
    }

    // MARK: Public API

    func profile(for ssid: String) -> NetworkProfile? {
        queue.sync { cache[ssid] }
    }

    func save(_ profile: NetworkProfile) {
        queue.async(flags: .barrier) {
            self.cache[profile.ssid] = profile
            self.persistToDisk()
        }
    }

    func delete(ssid: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: ssid)
            self.persistToDisk()
        }
    }

    func allProfiles() -> [NetworkProfile] {
        queue.sync { Array(cache.values).sorted { $0.ssid < $1.ssid } }
    }

    // MARK: Persistence

    private func loadFromDisk() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: NetworkProfile].self, from: data)
        else { return }
        cache = decoded
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: key)
    }
}
