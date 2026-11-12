import AppKit
import Carbon.HIToolbox
import PatchbeamCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Value snapshot for the pure geometry engine.
    var descriptor: ScreenDescriptor {
        ScreenDescriptor(
            id: String(displayID),
            localizedName: localizedName,
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeft: auxiliaryTopLeftArea,
            auxiliaryTopRight: auxiliaryTopRightArea,
            backingScale: backingScaleFactor,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
        )
    }
}

/// Global hotkey via Carbon `RegisterEventHotKey`, a public API that needs no Accessibility
/// or Input Monitoring permission. Default ⌃⌥Space.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    struct Combo: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        static let controlOptionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
        var display: String { "⌃⌥Space" }
    }

    private(set) var registeredCombo: Combo?
    private(set) var lastError: String?

    func register(_ combo: Combo = .controlOptionSpace, action: @escaping @MainActor () -> Void) {
        unregister()
        GlobalHotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5042_4D4B), id: 1)  // 'PBMK'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            registeredCombo = combo
            lastError = nil
        } else {
            // e.g. eventHotKeyExistsErr when another app owns the shortcut (conflict check).
            registeredCombo = nil
            lastError = "⌃⌥Space is already used by another app (error \(status)). Use the menu bar item instead."
        }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
