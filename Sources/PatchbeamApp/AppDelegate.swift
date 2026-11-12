import AppKit
import PatchbeamCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) weak var shared: AppDelegate?

    let model = AppModel()
    private var panel: NotchPanelController?
    private var statusItem: NSStatusItem?
    private let hotKey = GlobalHotKey()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var hideItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        panel = NotchPanelController(model: model)
        if ProcessInfo.processInfo.environment["PATCHBEAM_TIMING"] == "1" {
            // Measured after the panel is ordered front on screen; dyld/runtime setup before main is not included.
            FileHandle.standardError.write(Data(String(format: "timing: panel-visible %.0f ms after main\n", Date().timeIntervalSince(processStart) * 1000).utf8))
        }
        installStatusItem()
        hotKey.register { [weak self] in self?.model.toggleFromHotKey() }
        model.hotKeyStatus = hotKey.lastError
        Task {
            await model.bootstrap()
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") || ProcessInfo.processInfo.arguments.contains("--onboarding") {
                showOnboarding()
            }
            // Developer/demo affordance: `--open intake|expanded|demo` (documented in README).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--autodemo") {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                onboardingWindow?.close()
                await AutoDemo.run(model: model, recorder: panel?.recorder, geometry: { [weak self] in self?.panel?.geometryReport() ?? "" }) { line in
                    FileHandle.standardError.write(Data((line + "\n").utf8))
                }
                if args.contains("--quit-after") { NSApp.terminate(nil) }
                return
            }
            if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
                switch args[i + 1] {
                case "intake": model.beginIntake()
                case "expanded": model.open(.expanded)
                case "demo": await model.prepareDemo()
                default: break
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = PatchbeamGlyph.menuBarImage()
        item.button?.setAccessibilityLabel("Patchbeam")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "New Repair…", action: #selector(newRepair), keyEquivalent: " ").keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: "Open Cockpit", action: #selector(openCockpit), keyEquivalent: "")
        menu.addItem(withTitle: "Try the Demo Repair (no model)", action: #selector(runDemo), keyEquivalent: "")
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Notch Panel (privacy)", action: #selector(toggleHidden), keyEquivalent: "")
        menu.addItem(hide)
        hideItem = hide
        menu.addItem(withTitle: "Reset Panel Layout", action: #selector(resetLayout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        menu.addItem(withTitle: "Welcome Guide…", action: #selector(showOnboardingAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Patchbeam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for i in menu.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        hideItem?.state = (panel?.hidden ?? false) ? .on : .off
    }

    @objc private func newRepair() { panel?.hidden = false; model.beginIntake() }
    @objc private func openCockpit() { panel?.hidden = false; model.open(.expanded) }
    @objc private func runDemo() { panel?.hidden = false; Task { await model.prepareDemo() } }
    @objc private func toggleHidden() { panel?.hidden.toggle() }
    @objc private func resetLayout() { panel?.resetLayout() }
    @objc private func showSettingsAction() { showSettings() }
    @objc private func showOnboardingAction() { showOnboarding() }

    // MARK: Windows

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, resetLayout: { [weak self] in self?.panel?.resetLayout() })))
            w.title = "Patchbeam Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(model: model) { [weak self] in
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                self?.onboardingWindow?.close()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Welcome to Patchbeam"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}
