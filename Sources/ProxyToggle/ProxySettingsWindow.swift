import AppKit

// MARK: - Proxy Settings Window

/// Window controller for editing proxy host/port for the current (or a specific) SSID.
@MainActor
final class ProxySettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = ProxySettingsWindowController()

    private var window: NSWindow?
    private var targetSSID: String?

    // Controls
    private let ssidLabel        = NSTextField(labelWithString: "")
    private let httpHostField    = NSTextField()
    private let httpPortField    = NSTextField()
    private let httpsHostField   = NSTextField()
    private let httpsPortField   = NSTextField()
    private let useSameCheckbox  = NSButton(checkboxWithTitle: "Use same proxy for HTTPS", target: nil, action: nil)
    private let statusLabel      = NSTextField(labelWithString: "")
    private let saveButton       = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton     = NSButton(title: "Cancel", target: nil, action: nil)

    private override init() { super.init() }

    func show(ssid: String?) {
        if window == nil { buildWindow() }

        targetSSID = ssid
        populateFields(ssid: ssid)

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build Window

    private func buildWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Proxy Settings"
        w.delegate = self
        w.isReleasedWhenClosed = false

        let cv = NSView(frame: w.contentView!.bounds)
        cv.autoresizingMask = [.width, .height]
        w.contentView = cv

        // Style
        let bg = NSVisualEffectView(frame: cv.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        cv.addSubview(bg)

        buildFormLayout(in: cv)
        window = w
    }

    private func buildFormLayout(in parent: NSView) {
        let pad: CGFloat = 24
        var y = parent.bounds.height - 60

        // Network label
        ssidLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        ssidLabel.textColor = .secondaryLabelColor
        addLabel(ssidLabel, to: parent, y: &y, pad: pad)

        y -= 8

        // Section: HTTP Proxy
        addSectionHeader("HTTP Proxy", to: parent, y: &y, pad: pad)
        addFieldRow(label: "Host:", field: httpHostField, to: parent, y: &y, pad: pad)
        addFieldRow(label: "Port:", field: httpPortField, to: parent, y: &y, pad: pad)
        httpPortField.placeholderString = "8080"

        y -= 8

        // Same for HTTPS
        useSameCheckbox.frame = NSRect(x: pad, y: y - 22, width: 360 - pad*2, height: 22)
        useSameCheckbox.target = self
        useSameCheckbox.action = #selector(useSameChanged(_:))
        parent.addSubview(useSameCheckbox)
        y -= 30

        // Section: HTTPS Proxy
        addSectionHeader("HTTPS Proxy (if different)", to: parent, y: &y, pad: pad)
        addFieldRow(label: "Host:", field: httpsHostField, to: parent, y: &y, pad: pad)
        addFieldRow(label: "Port:", field: httpsPortField, to: parent, y: &y, pad: pad)

        y -= 8

        // Status label
        statusLabel.textColor = .systemRed
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.frame = NSRect(x: pad, y: y - 18, width: 360, height: 18)
        parent.addSubview(statusLabel)
        y -= 26

        // Buttons
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.frame = NSRect(x: parent.bounds.width - pad - 80, y: pad, width: 80, height: 32)
        saveButton.autoresizingMask = [.minXMargin]
        parent.addSubview(saveButton)

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.frame = NSRect(x: parent.bounds.width - pad - 170, y: pad, width: 80, height: 32)
        cancelButton.autoresizingMask = [.minXMargin]
        parent.addSubview(cancelButton)
    }

    private func addLabel(_ label: NSTextField, to parent: NSView, y: inout CGFloat, pad: CGFloat) {
        label.frame = NSRect(x: pad, y: y - 20, width: parent.bounds.width - pad*2, height: 20)
        label.autoresizingMask = [.width]
        parent.addSubview(label)
        y -= 28
    }

    private func addSectionHeader(_ text: String, to parent: NSView, y: inout CGFloat, pad: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.frame = NSRect(x: pad, y: y - 16, width: parent.bounds.width - pad*2, height: 16)
        parent.addSubview(label)
        y -= 22
    }

    private func addFieldRow(label labelText: String, field: NSTextField,
                             to parent: NSView, y: inout CGFloat, pad: CGFloat) {
        let rowH: CGFloat = 22
        let labelW: CGFloat = 44
        let fieldX = pad + labelW + 4

        let label = NSTextField(labelWithString: labelText)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 13)
        label.frame = NSRect(x: pad, y: y - rowH, width: labelW, height: rowH)
        parent.addSubview(label)

        field.frame = NSRect(x: fieldX, y: y - rowH, width: parent.bounds.width - fieldX - pad, height: rowH)
        field.bezelStyle = .roundedBezel
        field.autoresizingMask = [.width]
        parent.addSubview(field)

        y -= (rowH + 8)
    }

    // MARK: - Populate

    private func populateFields(ssid: String?) {
        if let ssid {
            ssidLabel.stringValue = "Network: \(ssid)"
            let p = ProfileStore.shared.profile(for: ssid) ?? NetworkProfile(ssid: ssid)
            httpHostField.stringValue = p.httpHost
            httpPortField.stringValue = "\(p.httpPort)"
            useSameCheckbox.state = p.useSameForHTTPS ? .on : .off
            httpsHostField.stringValue = p.useSameForHTTPS ? p.httpHost : p.httpsHost
            httpsPortField.stringValue = p.useSameForHTTPS ? "\(p.httpPort)" : "\(p.httpsPort)"
            httpsHostField.isEnabled = !p.useSameForHTTPS
            httpsPortField.isEnabled = !p.useSameForHTTPS
        } else {
            ssidLabel.stringValue = "No Wi-Fi connected"
        }
        statusLabel.stringValue = ""
    }

    // MARK: - Actions

    @objc private func useSameChanged(_ sender: NSButton) {
        let same = sender.state == .on
        httpsHostField.isEnabled = !same
        httpsPortField.isEnabled = !same
        if same {
            httpsHostField.stringValue = httpHostField.stringValue
            httpsPortField.stringValue = httpPortField.stringValue
        }
    }

    @objc private func save(_ sender: Any?) {
        guard let ssid = targetSSID else { window?.close(); return }

        // Validate
        let host = httpHostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            statusLabel.stringValue = "⚠ HTTP host cannot be empty."
            return
        }
        guard let port = Int(httpPortField.stringValue.trimmingCharacters(in: .whitespaces)),
              port > 0, port <= 65535 else {
            statusLabel.stringValue = "⚠ HTTP port must be 1–65535."
            return
        }
        let same = useSameCheckbox.state == .on
        var httpsH = host
        var httpsP = port
        if !same {
            httpsH = httpsHostField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !httpsH.isEmpty else {
                statusLabel.stringValue = "⚠ HTTPS host cannot be empty."
                return
            }
            guard let hp = Int(httpsPortField.stringValue.trimmingCharacters(in: .whitespaces)),
                  hp > 0, hp <= 65535 else {
                statusLabel.stringValue = "⚠ HTTPS port must be 1–65535."
                return
            }
            httpsP = hp
        }

        var profile = ProfileStore.shared.profile(for: ssid) ?? NetworkProfile(ssid: ssid)
        profile.httpHost = host
        profile.httpPort = port
        profile.useSameForHTTPS = same
        profile.httpsHost = httpsH
        profile.httpsPort = httpsP
        ProfileStore.shared.save(profile)

        // Re-apply if proxy is on for this SSID
        if profile.proxyEnabled {
            ProxyManager.shared.apply(profile)
        }

        window?.close()
    }

    @objc private func cancel(_ sender: Any?) {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {}
}
