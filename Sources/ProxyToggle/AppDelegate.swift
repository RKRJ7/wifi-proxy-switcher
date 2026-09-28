import AppKit
import ServiceManagement

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var statusItem: NSStatusItem!
    private var currentSSID: String?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startMonitoring()
        applyCurrentState()
        // Offer one-time silent-access setup on first launch if not yet configured
        promptForSilentAccessIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Proxy state left as-is on quit intentionally.
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        statusItem.menu = buildMenu()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        WiFiMonitor.shared.onSSIDChange = { [weak self] newSSID in
            guard let self else { return }
            self.handleSSIDChange(newSSID)
        }
        WiFiMonitor.shared.start()
    }

    private func handleSSIDChange(_ newSSID: String?) {
        let old = currentSSID
        currentSSID = newSSID
        guard newSSID != old else { return }

        if let ssid = newSSID {
            // Dispatch proxy change to a background thread so it never blocks the main thread
            // (sudo/osascript may take a moment)
            DispatchQueue.global(qos: .userInitiated).async {
                let profile = ProfileStore.shared.profile(for: ssid) ?? NetworkProfile(ssid: ssid)
                ProxyManager.shared.apply(profile)
            }
        }

        rebuildMenu()
        updateIcon()
    }

    // MARK: - Apply Current State on Launch

    private func applyCurrentState() {
        let ssid = WiFiMonitor.shared.readCurrentSSID()
        currentSSID = ssid
        if let ssid {
            DispatchQueue.global(qos: .userInitiated).async {
                let profile = ProfileStore.shared.profile(for: ssid) ?? NetworkProfile(ssid: ssid)
                ProxyManager.shared.apply(profile)
            }
        }
        updateIcon()
        rebuildMenu()
    }

    // MARK: - First-Launch Silent Access Prompt

    private func promptForSilentAccessIfNeeded() {
        // If we already have passwordless sudo, nothing to do.
        guard !ProxyManager.shared.hasSudoPrivileges else { return }

        // Check UserDefaults — don't nag if user already declined.
        let declinedKey = "SilentAccessPromptDeclined"
        guard !UserDefaults.standard.bool(forKey: declinedKey) else { return }

        // Small delay so the menu bar settles before showing a window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showSilentAccessAlert(declinedKey: declinedKey)
        }
    }

    private func showSilentAccessAlert(declinedKey: String) {
        let alert = NSAlert()
        alert.messageText = "Enable Silent Proxy Switching"
        alert.informativeText = """
            Right now, macOS asks for your admin password every time the proxy changes.

            WiFi Proxy Switcher can set up a one-time permission so proxy switching \
            happens silently in the background — no password dialogs ever again.

            This adds a single sudoers rule granting passwordless access to \
            /usr/sbin/networksetup only. You can remove it any time via the menu.
            """
        alert.addButton(withTitle: "Set Up (One-Time Password)")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let success = ProxyManager.shared.installSudoersRule()
            if success {
                let done = NSAlert()
                done.messageText = "Silent switching enabled ✓"
                done.informativeText = "From now on, proxy changes will happen automatically with no password prompts."
                done.addButton(withTitle: "Great!")
                done.alertStyle = .informational
                done.runModal()
                rebuildMenu() // Refresh to reflect new state
            } else {
                let fail = NSAlert()
                fail.messageText = "Setup cancelled"
                fail.informativeText = "You can try again any time via the menu: \"Enable Silent Proxy Switching\"."
                fail.addButton(withTitle: "OK")
                fail.alertStyle = .warning
                fail.runModal()
            }
        } else {
            // User said Not Now — remember so we don't ask again this install.
            UserDefaults.standard.set(true, forKey: declinedKey)
        }
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let ssid = currentSSID
        let proxyOn = ssid.flatMap { ProfileStore.shared.profile(for: $0)?.proxyEnabled } ?? false
        let symbolName = proxyOn ? "network" : "network.slash"
        let img = NSImage(systemSymbolName: symbolName,
                          accessibilityDescription: proxyOn ? "Proxy ON" : "Proxy OFF")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageOnly
    }

    // MARK: - Menu

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let ssid = WiFiMonitor.shared.readCurrentSSID()
        currentSSID = ssid
        let profile = ssid.flatMap { ProfileStore.shared.profile(for: $0) }
        let proxyOn = profile?.proxyEnabled ?? false
        let silentMode = ProxyManager.shared.hasSudoPrivileges

        // ── Status header ──
        let headerItem = NSMenuItem(title: proxyOn ? "Proxy: ON" : "Proxy: OFF",
                                    action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Wi-Fi SSID
        let wifiItem = NSMenuItem(title: ssid.map { "Wi-Fi: \($0)" } ?? "Wi-Fi: Not Connected",
                                   action: nil, keyEquivalent: "")
        wifiItem.isEnabled = false
        menu.addItem(wifiItem)

        // Proxy server info
        if proxyOn, let p = profile, !p.httpHost.isEmpty {
            let proxyInfo = NSMenuItem(title: "Server: \(p.httpHost):\(p.httpPort)",
                                       action: nil, keyEquivalent: "")
            proxyInfo.isEnabled = false
            menu.addItem(proxyInfo)
        }

        menu.addItem(.separator())

        // ── Toggle ──
        if ssid != nil {
            let toggleTitle = proxyOn ? "Turn Proxy OFF" : "Turn Proxy ON"
            let toggleItem = NSMenuItem(title: toggleTitle,
                                        action: #selector(toggleProxy(_:)),
                                        keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
            menu.addItem(.separator())
        }

        // ── Settings / Profiles ──
        let settingsItem = NSMenuItem(title: "Proxy Settings…",
                                      action: #selector(openProxySettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let profilesItem = NSMenuItem(title: "Wi-Fi Profiles…",
                                      action: #selector(openProfilesWindow(_:)),
                                      keyEquivalent: "")
        profilesItem.target = self
        menu.addItem(profilesItem)

        menu.addItem(.separator())

        // ── Silent access ──
        if silentMode {
            let silentItem = NSMenuItem(title: "✓ Silent Switching Active",
                                        action: nil, keyEquivalent: "")
            silentItem.isEnabled = false
            menu.addItem(silentItem)

            let revokeItem = NSMenuItem(title: "Revoke Silent Access…",
                                        action: #selector(revokeSilentAccess(_:)),
                                        keyEquivalent: "")
            revokeItem.target = self
            menu.addItem(revokeItem)
        } else {
            let setupItem = NSMenuItem(title: "Enable Silent Proxy Switching…",
                                       action: #selector(setupSilentAccess(_:)),
                                       keyEquivalent: "")
            setupItem.target = self
            menu.addItem(setupItem)
        }

        menu.addItem(.separator())

        // ── Launch at Login ──
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                           action: #selector(toggleLaunchAtLogin(_:)),
                                           keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        // ── Quit ──
        let quitItem = NSMenuItem(title: "Quit WiFi Proxy Switcher",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func rebuildMenu() {
        statusItem.menu = buildMenu()
    }

    // MARK: - Actions

    @objc private func toggleProxy(_ sender: Any?) {
        guard let ssid = currentSSID else { return }
        var profile = ProfileStore.shared.profile(for: ssid) ?? NetworkProfile(ssid: ssid)
        profile.proxyEnabled.toggle()
        ProfileStore.shared.save(profile)
        updateIcon()
        rebuildMenu()
        // Apply on background thread to avoid any UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            ProxyManager.shared.apply(profile)
        }
    }

    @objc private func openProxySettings(_ sender: Any?) {
        ProxySettingsWindowController.shared.show(ssid: currentSSID)
    }

    @objc private func openProfilesWindow(_ sender: Any?) {
        ProfilesWindowController.shared.show()
    }

    @objc private func setupSilentAccess(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: "SilentAccessPromptDeclined")
        showSilentAccessAlert(declinedKey: "SilentAccessPromptDeclined")
    }

    @objc private func revokeSilentAccess(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Revoke Silent Access?"
        alert.informativeText = "The sudoers rule for networksetup will be removed. Proxy changes will ask for your admin password again."
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ProxyManager.shared.removeSudoersRule()
        UserDefaults.standard.removeObject(forKey: "SilentAccessPromptDeclined")
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        setLoginItem(enabled: !isLoginItemEnabled())
        rebuildMenu()
    }

    // MARK: - Launch at Login (ServiceManagement)

    private func isLoginItemEnabled() -> Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func setLoginItem(enabled: Bool) {
        if #available(macOS 13, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[LaunchAtLogin] Error: \(error)")
            }
        }
    }
}
