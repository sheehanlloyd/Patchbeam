import AppKit

// AppKit lifecycle: a menu-bar agent app (LSUIElement) whose UI lives in the notch panel.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
