import AppKit

// MARK: - Wi-Fi Profiles Window

/// Window controller that lists all saved per-SSID profiles, allows editing and deletion.
@MainActor
final class ProfilesWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = ProfilesWindowController()
    private override init() { super.init() }

    private var window: NSWindow?
    private var tableView: NSTableView!
    private var profiles: [NetworkProfile] = []

    // MARK: - Show

    func show() {
        if window == nil { buildWindow() }
        reload()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build Window

    private func buildWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Wi-Fi Profiles"
        w.minSize = NSSize(width: 420, height: 300)
        w.delegate = self
        w.isReleasedWhenClosed = false

        let cv = w.contentView!

        // Visual effect background
        let bg = NSVisualEffectView(frame: cv.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        cv.addSubview(bg)

        // Scroll view + table
        let scroll = NSScrollView(frame: cv.bounds.insetBy(dx: 0, dy: 44))
        scroll.frame.origin = NSPoint(x: 0, y: 44)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let tv = NSTableView()
        tv.usesAlternatingRowBackgroundColors = true
        tv.rowHeight = 54
        tv.intercellSpacing = NSSize(width: 0, height: 1)
        tv.dataSource = self
        tv.delegate = self

        let ssidCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ssid"))
        ssidCol.title = "Wi-Fi Network"
        ssidCol.width = 160
        ssidCol.minWidth = 100

        let proxyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("proxy"))
        proxyCol.title = "Proxy"
        proxyCol.width = 180
        proxyCol.minWidth = 120

        let toggleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("toggle"))
        toggleCol.title = "Enabled"
        toggleCol.width = 70
        toggleCol.minWidth = 60

        let deleteCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("delete"))
        deleteCol.title = ""
        deleteCol.width = 60
        deleteCol.minWidth = 50

        tv.addTableColumn(ssidCol)
        tv.addTableColumn(proxyCol)
        tv.addTableColumn(toggleCol)
        tv.addTableColumn(deleteCol)

        scroll.documentView = tv
        tableView = tv
        cv.addSubview(scroll)

        // Bottom bar
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: cv.bounds.width, height: 44))
        bottomBar.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(bottomBar)

        let sep = NSBox(frame: NSRect(x: 0, y: 43, width: cv.bounds.width, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width]
        bottomBar.addSubview(sep)

        let closeBtn = NSButton(title: "Done", target: self, action: #selector(closeWindow(_:)))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.frame = NSRect(x: cv.bounds.width - 104, y: 8, width: 80, height: 28)
        closeBtn.autoresizingMask = [.minXMargin]
        bottomBar.addSubview(closeBtn)

        let noteLabel = NSTextField(labelWithString: "Changes apply immediately when on the selected Wi-Fi.")
        noteLabel.font = NSFont.systemFont(ofSize: 11)
        noteLabel.textColor = .tertiaryLabelColor
        noteLabel.frame = NSRect(x: 16, y: 14, width: 340, height: 16)
        noteLabel.autoresizingMask = [.width]
        bottomBar.addSubview(noteLabel)

        window = w
    }

    // MARK: - Data

    private func reload() {
        profiles = ProfileStore.shared.allProfiles()
        tableView?.reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        profiles.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < profiles.count else { return nil }
        let profile = profiles[row]
        let id = tableColumn?.identifier.rawValue ?? ""

        switch id {
        case "ssid":
            let cell = makeLabel(identifier: "ssidCell")
            cell.stringValue = profile.ssid
            cell.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            return cell

        case "proxy":
            let cell = makeLabel(identifier: "proxyCell")
            if !profile.httpHost.isEmpty {
                cell.stringValue = "\(profile.httpHost):\(profile.httpPort)"
            } else {
                cell.stringValue = "—"
                cell.textColor = .tertiaryLabelColor
            }
            cell.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            return cell

        case "toggle":
            let id = NSUserInterfaceItemIdentifier("toggleCell")
            var cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSButton
            if cell == nil {
                cell = NSButton(checkboxWithTitle: "", target: nil, action: nil)
                cell!.identifier = id
            }
            cell!.state = profile.proxyEnabled ? .on : .off
            cell!.tag = row
            cell!.target = self
            cell!.action = #selector(toggleProfile(_:))
            return cell!

        case "delete":
            let id = NSUserInterfaceItemIdentifier("deleteCell")
            var cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSButton
            if cell == nil {
                cell = NSButton(title: "Forget", target: nil, action: nil)
                cell!.bezelStyle = .inline
                cell!.identifier = id
            }
            cell!.tag = row
            cell!.target = self
            cell!.action = #selector(forgetProfile(_:))
            return cell!

        default:
            return nil
        }
    }

    private func makeLabel(identifier: String) -> NSTextField {
        let id = NSUserInterfaceItemIdentifier(identifier)
        if let existing = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
            existing.textColor = .labelColor
            return existing
        }
        let label = NSTextField(labelWithString: "")
        label.identifier = id
        return label
    }

    // MARK: - Row Actions

    @objc private func toggleProfile(_ sender: NSButton) {
        let row = sender.tag
        guard row < profiles.count else { return }
        var profile = profiles[row]
        profile.proxyEnabled = sender.state == .on
        ProfileStore.shared.save(profile)

        // Auto-apply if the current SSID matches
        if let current = WiFiMonitor.shared.currentSSID, current == profile.ssid {
            ProxyManager.shared.apply(profile)
        }

        reload()
    }

    @objc private func forgetProfile(_ sender: NSButton) {
        let row = sender.tag
        guard row < profiles.count else { return }
        let profile = profiles[row]

        let alert = NSAlert()
        alert.messageText = "Forget \"\(profile.ssid)\"?"
        alert.informativeText = "The saved proxy preference for this Wi-Fi network will be deleted. Reconnecting to it will default to proxy OFF."
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard let w = window else { return }
        alert.beginSheetModal(for: w) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            ProfileStore.shared.delete(ssid: profile.ssid)
            self.reload()
        }
    }

    // MARK: - Close

    @objc private func closeWindow(_ sender: Any?) {
        window?.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {}
}
