import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let vioHotkeyDidChange = Notification.Name("VioHotkeyDidChange")
}

/// A global shortcut: virtual key code plus device-independent modifier flags.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        KeyDisplay.string(keyCode: keyCode, modifiers: flags)
    }

    static let standard = Hotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: NSEvent.ModifierFlags.option.rawValue
    )
}

enum AppSettings {
    private static let hotkeyKey = "VioHotkey"

    static var hotkey: Hotkey {
        guard let data = UserDefaults.standard.data(forKey: hotkeyKey),
              let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return .standard
        }
        return hotkey
    }

    static func setHotkey(_ hotkey: Hotkey) throws {
        let data = try JSONEncoder().encode(hotkey)
        try HotkeyCenter.shared.update(hotkey: hotkey)
        UserDefaults.standard.set(data, forKey: hotkeyKey)
        NotificationCenter.default.post(name: .vioHotkeyDidChange, object: nil)
    }

    static var pushToTalk: Bool {
        get { UserDefaults.standard.object(forKey: "VioPushToTalk") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "VioPushToTalk") }
    }

    static var cleanupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "VioCleanupEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "VioCleanupEnabled") }
    }

    /// ISO code; English by default, "auto" to let the model detect per clip.
    static var language: String {
        get { UserDefaults.standard.string(forKey: "VioLanguage") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "VioLanguage") }
    }

    /// Names/jargon for the engine's keyword biasing, normalized to the
    /// newline-separated form needle_transcribe expects.
    static var keywords: String {
        get {
            normalizedKeywords(UserDefaults.standard.string(forKey: "VioKeywords") ?? "")
        }
        set { UserDefaults.standard.set(newValue, forKey: "VioKeywords") }
    }

    static func normalizedKeywords(_ words: String) -> String {
        words.split(whereSeparator: { ",\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum KeyDisplay {
    private static let specialNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_Help): "Help",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
    ]

    static func string(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        return prefix + keyName(keyCode: keyCode)
    }

    static func keyName(keyCode: UInt32) -> String {
        if let name = specialNames[keyCode] { return name }
        if let char = unicodeCharacter(forVirtualKey: CGKeyCode(keyCode)), !char.isEmpty {
            return char.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// Translates a virtual key code to its character for the current keyboard layout.
    private static func unicodeCharacter(forVirtualKey keyCode: CGKeyCode) -> String? {
        guard let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var length = 0
        var characters = [UniChar](repeating: 0, count: maxLength)
        let result = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                maxLength,
                &length,
                &characters
            )
        }
        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
