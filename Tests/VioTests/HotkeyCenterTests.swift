import Carbon.HIToolbox
import XCTest
@testable import Vio

final class HotkeyCenterTests: XCTestCase {
    func testConflictPreservesPreviousRegistration() throws {
        var references: [EventHotKeyRef] = []
        defer { references.forEach { UnregisterEventHotKey($0) } }
        let modifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        var available: [Hotkey] = []
        for code in [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), modifiers.carbonFlags,
                                            EventHotKeyID(signature: 0x7465_7374, id: UInt32(code)),
                                            GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                references.append(ref)
                available.append(Hotkey(keyCode: UInt32(code), modifiers: modifiers.rawValue))
            }
            if available.count == 2 { break }
        }
        guard available.count == 2 else { throw XCTSkip("Two unused test shortcuts are required.") }
        // Release one shortcut for Vio. Keep the other registered to create a conflict.
        UnregisterEventHotKey(references.removeFirst())
        let center = HotkeyCenter.shared
        try center.update(hotkey: available[0])
        XCTAssertNoThrow(try center.update(hotkey: available[0]))
        XCTAssertThrowsError(try center.update(hotkey: available[1]))
        var probe: EventHotKeyRef?
        let status = RegisterEventHotKey(available[0].keyCode, modifiers.carbonFlags,
                                        EventHotKeyID(signature: 0x7465_7374, id: 100),
                                        GetApplicationEventTarget(), 0, &probe)
        if let probe { references.append(probe) }
        XCTAssertNotEqual(status, noErr, "Vio must retain its previous shortcut after a failed change.")
        UnregisterEventHotKey(references.removeFirst())
        XCTAssertNoThrow(try center.update(hotkey: available[1]))
    }
}
