import AppKit
import PatchbeamCore
import SwiftUI

/// Borderless, non-activating panel. It only becomes key when the user explicitly opens the
/// cockpit or intake (click/hotkey), never because of a passive status change (PB-001).
final class NotchPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        // Documented, compatible flags: visible on every Space and beside full-screen apps,
        // not part of window cycling. (canJoinAllSpaces and moveToActiveSpace are exclusive.)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        setAccessibilityLabel("Patchbeam")
        setAccessibilityRole(.popover)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController {
    let model: AppModel
    let panel = NotchPanel()
    let engine = NotchGeometryEngine()
    private(set) var geometry: NotchGeometry?
    private(set) var screen: ScreenDescriptor?
    private var shrinkWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    let layout = PanelLayoutState()
    private(set) var recorder: EvidenceRecorder?

    static let contentHeights: [PanelPresentation: CGFloat] = [.dormant: 0, .glance: 0, .expanded: 470, .intake: 500]

    init(model: AppModel) {
        self.model = model
        let root = NotchRootView(model: model, layout: layout)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        recorder = EvidenceRecorder(view: hosting)
        model.onPresentationChange = { [weak self] p in self?.present(p) }
        model.onRequestKeyFocus = { [weak self] in self?.focus() }
        observe()
        relayout(animated: false)
    }

    var hidden = false {
        didSet { hidden ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    }

    private func observe() {
        let nc = NotificationCenter.default
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout(animated: false) }
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.relayout(animated: false) }
            })
        }
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pref = UserDefaults.standard.string(forKey: "preferredScreenID")
                if pref != self.screen?.id, NSScreen.screens.contains(where: { String($0.displayID) == pref }) { self.relayout(animated: false) }
            }
        })
    }

    /// Recompute geometry for the chosen display. If the preferred display was unplugged, the
    /// engine re-homes to the notched/built-in/first screen.
    func relayout(animated: Bool) {
        let screens = NSScreen.screens.map(\.descriptor)
        guard let s = engine.selectScreen(screens, preferredID: UserDefaults.standard.string(forKey: "preferredScreenID")) else { return }
        screen = s
        let g = engine.geometry(for: s)
        geometry = g
        layout.geometry = g
        layout.shapeSize = engine.shapeSize(for: model.presentation, geometry: g, contentHeight: Self.contentHeights[model.presentation] ?? 0)
        layout.presentation = model.presentation
        panel.setFrame(engine.panelFrame(for: model.presentation, geometry: g, contentHeight: Self.contentHeights[model.presentation] ?? 0), display: true)
        if !hidden { panel.orderFrontRegardless() }
    }

    func present(_ p: PanelPresentation) {
        guard let g = geometry else { return }
        let target = engine.panelFrame(for: p, geometry: g, contentHeight: Self.contentHeights[p] ?? 0)
        let shape = engine.shapeSize(for: p, geometry: g, contentHeight: Self.contentHeights[p] ?? 0)
        shrinkWork?.cancel()
        let current = panel.frame
        let grows = target.width >= current.width || target.height >= current.height
        if grows {
            // Grow the window first (top-anchored), then let SwiftUI spring the shape outward.
            panel.setFrame(target.union(current).intersection(g.screenFrame), display: true)
        }
        layout.presentation = p
        withAnimation(layout.animation) { layout.shapeSize = shape }
        let finalize = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.setFrame(target, display: true)
        }
        shrinkWork = finalize
        DispatchQueue.main.asyncAfter(deadline: .now() + (layout.reduceMotion ? 0.2 : 0.38), execute: finalize)

        panel.allowsKey = p == .expanded || p == .intake
        if !panel.allowsKey, panel.isKeyWindow { panel.resignKey() }
    }

    func focus() {
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
    }

    func resetLayout() {
        UserDefaults.standard.removeObject(forKey: "preferredScreenID")
        relayout(animated: false)
    }
}

/// Animated layout values shared with SwiftUI.
@MainActor
@Observable
final class PanelLayoutState {
    var geometry: NotchGeometry?
    var shapeSize: CGSize = .zero
    var presentation: PanelPresentation = .dormant

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || UserDefaults.standard.bool(forKey: "reduceMotionOverride")
    }

    /// Spring ≈ 280 ms; reduced motion becomes a short crossfade-like ease (PRD §7.3).
    var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 0.84)
    }
}
