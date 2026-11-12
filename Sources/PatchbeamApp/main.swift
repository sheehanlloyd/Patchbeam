import AppKit

// AppKit lifecycle: a menu-bar agent app (LSUIElement) whose UI lives in the notch panel.
/// Process start for the opt-in startup timing log (PATCHBEAM_TIMING=1).
let processStart = Date()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
