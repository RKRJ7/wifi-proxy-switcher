<h1 align="center">WiFi Proxy Switcher</h1>

<p align="center">
  A lightweight, native macOS menu-bar app that automatically applies the correct HTTP/HTTPS system proxy whenever you switch Wi-Fi networks — with per-SSID memory.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.10-orange?logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen" alt="SPM compatible">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

---

## ✨ Features

| Feature | Detail |
|---|---|
| **Per-SSID proxy memory** | Each Wi-Fi network remembers its own proxy ON/OFF state and host/port |
| **Automatic switching** | Proxy config applied instantly when you join a known Wi-Fi |
| **Safe defaults** | Unknown networks always start with proxy OFF |
| **Native menu-bar icon** | SF Symbol template icon adapts to light/dark mode |
| **Proxy Settings UI** | Edit HTTP/HTTPS host and port per network |
| **Wi-Fi Profiles UI** | Browse, toggle, and forget saved Wi-Fi profiles |
| **Launch at Login** | Optional via `SMAppService` (macOS 13+) |
| **No Dock icon** | Pure menu-bar utility, zero visual clutter |

---

## 📋 Requirements

- **macOS 13 Ventura** or later (tested on macOS 26 Tahoe)
- Apple Silicon or Intel Mac
- **Xcode Command Line Tools** — no full Xcode install needed
- Administrator password to change system proxy settings (prompted once per change)

Install CLT if you don't have them:
```bash
xcode-select --install
```

---

## 🚀 Build & Install

```bash
# 1. Clone the repo
git clone https://github.com/RKRJ7/wifi-proxy-switcher.git
cd wifi-proxy-switcher

# 2. Build (debug — fast, for testing)
./build.sh

# 3. Run directly from the project folder
open WiFiProxySwitcher.app

# 4. Install permanently to /Applications
cp -r WiFiProxySwitcher.app /Applications/
open /Applications/WiFiProxySwitcher.app

# 5. Build an optimized release binary
./build.sh --release
```

> **First-launch prompt:** macOS will ask for Location Services permission to read the current Wi-Fi SSID. Grant *"While Using the App"* — your physical location is never stored or used.

---

## 🔐 Required macOS Permissions

### Location Services

macOS 14 Sonoma and later require Location Services permission for apps to read the Wi-Fi SSID via CoreWLAN. Without it, `CWInterface.ssid()` returns `nil`.

> **What is accessed:** Only the Wi-Fi network name (SSID).  
> **What is never done:** Store, transmit, or use your geographic position.

You can review this at any time in:  
**System Settings → Privacy & Security → Location Services → WiFi Proxy Switcher**

### Administrator Password

When you turn a proxy ON or OFF, the app calls `/usr/sbin/networksetup` with write arguments. macOS requires administrator authorisation for this — an auth dialog appears once per session.

---

## 🧠 How It Works

### SSID Detection

```
App starts
  └─ CWWiFiClient.shared().interface().ssid()   ← read current SSID
       CWWiFiClient delegates: ssidDidChangeForWiFiInterface
         └─ fires whenever Wi-Fi network changes
              └─ WiFiMonitor calls onSSIDChange callback
                   └─ AppDelegate handles the new SSID
```

`CoreWLAN` (`CWWiFiClient`) registers for `ssidDidChange` events. Every event triggers a re-read of the SSID and re-application of the matching saved profile.

### Proxy Switching

```
New SSID detected
  └─ Look up ProfileStore[ssid]
       ├─ Found     →  apply saved profile (enable/disable proxy + set host:port)
       └─ Not found →  create default profile (proxyEnabled: false), leave proxy off

apply(profile):
  proxyEnabled == true:
    networksetup -setwebproxy         "Wi-Fi" <host> <port>
    networksetup -setwebproxystate    "Wi-Fi" on
    networksetup -setsecurewebproxy   "Wi-Fi" <host> <port>
    networksetup -setsecurewebproxystate "Wi-Fi" on
  proxyEnabled == false:
    networksetup -setwebproxystate       "Wi-Fi" off
    networksetup -setsecurewebproxystate "Wi-Fi" off
```

### Persistence

Profiles are stored in `UserDefaults` under key `WiFiProxyProfiles_v1` as a JSON-encoded `[String: NetworkProfile]` dictionary. Data survives app restarts and Mac reboots.

<details>
<summary>Example stored JSON</summary>

```json
{
  "Office-WiFi": {
    "ssid": "Office-WiFi",
    "proxyEnabled": true,
    "httpHost": "172.31.2.4",
    "httpPort": 8080,
    "httpsHost": "172.31.2.4",
    "httpsPort": 8080,
    "useSameForHTTPS": true
  },
  "Home-WiFi": {
    "ssid": "Home-WiFi",
    "proxyEnabled": false,
    "httpHost": "",
    "httpPort": 8080,
    "httpsHost": "",
    "httpsPort": 8080,
    "useSameForHTTPS": true
  }
}
```
</details>

---

## 🗂 Project Structure

```
wifi-proxy-switcher/
├── Package.swift                  Swift Package Manager manifest
├── build.sh                       Build + bundle script
├── Resources/
│   └── Info.plist                 App bundle metadata & permissions
└── Sources/ProxyToggle/
    ├── main.swift                 Entry point
    ├── AppDelegate.swift          Menu bar, SSID events, user actions
    ├── WiFiMonitor.swift          CoreWLAN SSID detection + CLLocation
    ├── ProxyManager.swift         networksetup read/write wrapper
    ├── ProfileStore.swift         Per-SSID data model + UserDefaults persistence
    ├── ProxySettingsWindow.swift  Proxy host/port editor UI
    └── ProfilesWindow.swift       Wi-Fi profiles list UI
```

---

## 🖥 Menu Structure

```
[network icon]

Proxy: ON                ← current state (not clickable)
Wi-Fi: Office-WiFi       ← current SSID  (not clickable)
Proxy: 172.31.2.4:8080   ← shown when proxy is on

─────────────────────────
Turn Proxy OFF           ← toggles only the current SSID's profile
─────────────────────────
Proxy Settings…          ← edit host/port for current SSID
Wi-Fi Profiles…          ← manage all saved SSIDs
─────────────────────────
Launch at Login          ← checkmark toggle
─────────────────────────
Quit WiFi Proxy Switcher
```

---

## 🔄 Launch at Login

Uses `SMAppService.mainApp` (macOS 13+). Toggle via the menu item. When enabled, macOS launches the app automatically at login, which then:

1. Reads the current SSID
2. Looks up the saved profile
3. Applies the proxy (or leaves it off for unknown networks)

---

## ⚠️ Edge Cases

| Situation | Behaviour |
|---|---|
| No Wi-Fi / Ethernet only | UI shows "Not Connected", proxy untouched |
| Unknown SSID | Default: proxy OFF, profile created on first manual toggle |
| Wi-Fi drops & reconnects | SSID change event fires → correct profile re-applied |
| Invalid host/port | Validation error shown before saving |
| Location permission denied | SSID returns nil; proxy not changed; icon shows disconnected state |
| User changes proxy in System Settings | App state may diverge; toggling in app will re-sync |

---

## 📄 License

This project is released under the [MIT License](LICENSE).

---

<p align="center">Made with ❤️ for macOS power users who juggle multiple networks</p>
