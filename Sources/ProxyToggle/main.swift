import AppKit

// Initialize NSApplication first — this sets NSApp (the shared singleton).
let app = NSApplication.shared

// main.swift runs on the main thread. Tell Swift's concurrency system.
MainActor.assumeIsolated {
    // Pure menu-bar app: no Dock icon.
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
