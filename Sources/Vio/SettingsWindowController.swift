import AppKit
import SwiftUI

extension Notification.Name {
    static let vioSettingsWillOpen = Notification.Name("VioSettingsWillOpen")
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var positioned = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 730),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vio Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        NotificationCenter.default.post(name: .vioSettingsWillOpen, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        if !positioned {
            window?.center()
            positioned = true
        }
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
    }
}
