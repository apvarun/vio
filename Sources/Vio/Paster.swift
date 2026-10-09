import AppKit
import ApplicationServices

enum Paster {
    private static let vKeyCode: CGKeyCode = 9
    private static let systemWide = AXUIElementCreateSystemWide()

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// The text field focused when dictation started, if Accessibility is granted.
    static func captureFocusedElement() -> AXUIElement? {
        guard isTrusted, let raw = rawFocusedElement() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    /// AppKit screen rect of the caret in `element`, for the recording
    /// indicator. nil when the app doesn't expose caret bounds.
    static func caretRect(for element: AXUIElement?) -> CGRect? {
        guard let element else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue) == .success,
              let boundsValue else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(boundsValue, to: AXValue.self), .cgRect, &rect),
              rect.width > 0 || rect.height > 0,
              let primaryHeight = NSScreen.screens.first?.frame.maxY else { return nil }
        // AX/Quartz coordinates are top-left origin; AppKit's are bottom-left.
        return CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Delivers the transcript: ⌘V when focus never left the captured field
    /// (so the target app's undo still works), direct AX insertion when focus
    /// moved mid-dictation, clipboard + ⌘V if AX insertion fails, and a plain
    /// clipboard copy as the last resort. Returns false only when nothing but
    /// the clipboard copy was possible.
    @discardableResult
    static func pasteOrCopy(_ text: String, into target: AXUIElement?) -> Bool {
        let frontIsSelf = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        guard !frontIsSelf, isTrusted else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            NSLog("vio paste: clipboard only (%@)", frontIsSelf ? "Vio is frontmost" : "Accessibility not granted")
            return false
        }

        if let target, focusMoved(from: target),
           AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            NSLog("vio paste: inserted into captured field")
            return true
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()
        NSLog("vio paste: ⌘V posted")

        // Wait 0.4 s for the target app to read the clipboard before restoring it.
        // Keep any text the user copied in the meantime.
        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [text] in
                if pasteboard.string(forType: .string) == text {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
        return true
    }

    /// The system-wide focused element as a raw CF value, or nil. Uses the
    /// attribute API to read the focused element.
    private static func rawFocusedElement() -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func focusMoved(from target: AXUIElement) -> Bool {
        guard let raw = rawFocusedElement() else { return true }
        return !CFEqual(unsafeBitCast(raw, to: AXUIElement.self), target)
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
