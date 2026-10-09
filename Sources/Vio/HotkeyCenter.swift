import AppKit
import Carbon.HIToolbox

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

/// Registers a single system-wide hotkey via the Carbon hot-key manager.
/// Carbon requires no Accessibility permission and reports key release
/// for push-to-talk.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// Called on the main thread with `true` on key-down, `false` on key-up.
    var onTrigger: ((Bool) -> Void)?

    private var activeHotkey: Hotkey?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x7669_6F31 // 'vio1'

    func update(hotkey: Hotkey) throws {
        if hotKeyRef != nil, activeHotkey == hotkey { return }
        try installEventHandlerIfNeeded()

        let carbonMods = hotkey.flags.carbonFlags
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            carbonMods,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            unregister()
            hotKeyRef = ref
            activeHotkey = hotkey
            NSLog("Vio: hotkey registered (\(hotkey.displayString))")
        } else {
            throw HotkeyError.registrationFailed(hotkey.displayString, status)
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }

        let handlerUPP: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if hotKeyID.signature == 0x7669_6F31 {
                let pressed = GetEventKind(event) == EventKind(kEventHotKeyPressed)
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { center.onTrigger?(pressed) }
            }
            return noErr
        }

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            2,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw HotkeyError.handlerFailed(status) }
    }
}

enum HotkeyError: LocalizedError {
    case registrationFailed(String, OSStatus)
    case handlerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let shortcut, let status):
            return "Could not register \(shortcut). Another app may use it. Choose a different shortcut in Settings. Error code: \(status)."
        case .handlerFailed(let status):
            return "Could not listen for shortcut events. Restart Vio and try again. Error code: \(status)."
        }
    }
}
