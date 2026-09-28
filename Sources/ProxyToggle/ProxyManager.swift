import Foundation
import SystemConfiguration

// MARK: - Proxy Manager

/// Manages reading and writing macOS system HTTP/HTTPS proxy via networksetup.
///
/// Privilege Strategy (in order of preference):
///   1. `sudo -n networksetup ...`  — zero prompts after one-time sudoers setup.
///   2. Single batched osascript    — at most ONE admin prompt per WiFi switch.
///
/// Call `ProxyManager.shared.ensurePrivilegesSetup()` on first launch to install
/// the sudoers rule (one-time admin prompt, never asked again).
final class ProxyManager {

    static let shared = ProxyManager()
    private init() {}

    /// Path to the sudoers drop-in file installed by this app.
    static let sudoersPath = "/etc/sudoers.d/wifi-proxy-switcher"

    // MARK: - Privilege Check

    /// Returns true if passwordless sudo for networksetup is already configured.
    var hasSudoPrivileges: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // -n = non-interactive (fail immediately if password would be required)
        // -l = list what this user can run; combined: checks without prompting
        task.arguments = ["-n", "/usr/sbin/networksetup", "-listallnetworkservices"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    /// Install the sudoers drop-in rule (one-time, requires ONE admin prompt).
    /// After this succeeds, all future proxy changes happen silently.
    /// Returns true on success.
    @discardableResult
    func installSudoersRule() -> Bool {
        // The rule grants the current user passwordless access to networksetup only.
        guard let username = ProcessInfo.processInfo.environment["USER"] ?? ProcessInfo.processInfo.environment["LOGNAME"] else {
            return false
        }
        let rule = "\(username) ALL=(ALL) NOPASSWD: /usr/sbin/networksetup\n"
        // Write to sudoers.d via a single osascript (ONE prompt, never again after this)
        let safeRule = rule.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "echo \\"\(safeRule)\\" > \(ProxyManager.sudoersPath) && chmod 440 \(ProxyManager.sudoersPath)" with administrator privileges
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    /// Remove the sudoers rule (used by Uninstall or reset).
    func removeSudoersRule() {
        let script = "do shell script \"rm -f \(ProxyManager.sudoersPath)\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Apply Proxy

    /// Apply (or clear) the system proxy for the given Wi-Fi service.
    func apply(_ profile: NetworkProfile, toService serviceName: String = "Wi-Fi") {
        if profile.proxyEnabled {
            enableProxy(
                httpHost: profile.httpHost, httpPort: profile.httpPort,
                httpsHost: profile.effectiveHTTPSHost, httpsPort: profile.effectiveHTTPSPort,
                serviceName: serviceName
            )
        } else {
            disableProxy(serviceName: serviceName)
        }
    }

    /// Disable HTTP/HTTPS proxy on the given network service.
    func disableProxy(serviceName: String = "Wi-Fi") {
        runWriteCommands([
            ["-setwebproxystate",    serviceName, "off"],
            ["-setsecurewebproxystate", serviceName, "off"],
        ])
    }

    // MARK: - Read Current State

    /// Returns true if the system HTTP proxy is currently enabled for the given service.
    func isProxyEnabled(serviceName: String = "Wi-Fi") -> Bool {
        let output = runNetworkSetupOutput(args: ["-getwebproxy", serviceName])
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("enabled:") {
                return trimmed.lowercased().contains("yes")
            }
        }
        return false
    }

    /// Returns current HTTP proxy server string "host:port" or nil.
    func currentProxyString(serviceName: String = "Wi-Fi") -> String? {
        let output = runNetworkSetupOutput(args: ["-getwebproxy", serviceName])
        var host: String?
        var port: String?
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("server:") {
                host = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("port:") {
                port = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        guard let h = host, !h.isEmpty, let p = port, !p.isEmpty else { return nil }
        return "\(h):\(p)"
    }

    // MARK: - Private: Enable Proxy

    private func enableProxy(httpHost: String, httpPort: Int,
                             httpsHost: String, httpsPort: Int,
                             serviceName: String)
    {
        // All 4 commands batched into one privilege call — at most 1 prompt if sudo not set up.
        runWriteCommands([
            ["-setwebproxy",             serviceName, httpHost,  "\(httpPort)"],
            ["-setwebproxystate",        serviceName, "on"],
            ["-setsecurewebproxy",       serviceName, httpsHost, "\(httpsPort)"],
            ["-setsecurewebproxystate",  serviceName, "on"],
        ])
    }

    // MARK: - Private: Batched Write

    /// Runs multiple networksetup write commands.
    /// Uses sudo (no prompt) if privileged, otherwise ONE batched osascript prompt.
    private func runWriteCommands(_ commandArgSets: [[String]]) {
        if hasSudoPrivileges {
            // Fast path: sudo -n — no password dialog ever.
            for args in commandArgSets {
                runWithSudo(args: args)
            }
        } else {
            // Fallback: batch ALL commands into a SINGLE osascript → max 1 prompt.
            runBatchedOsascript(commandArgSets)
        }
    }

    /// Run networksetup via passwordless sudo.
    @discardableResult
    private func runWithSudo(args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/sbin/networksetup"] + args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    /// Runs all networksetup commands in a SINGLE osascript block — only ONE admin prompt.
    @discardableResult
    private func runBatchedOsascript(_ commandArgSets: [[String]]) -> Int32 {
        // Build one shell string with all commands chained with &&
        let shellCmds = commandArgSets.map { args -> String in
            let quotedArgs = args.map { arg in
                // Shell-quote each argument
                "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'"
            }.joined(separator: " ")
            return "/usr/sbin/networksetup \(quotedArgs)"
        }.joined(separator: " && ")

        // osascript single-quotes: escape the shell string for the AppleScript string literal
        let escaped = shellCmds
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    // MARK: - Private: Read (no privilege needed)

    private func runNetworkSetupOutput(args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
