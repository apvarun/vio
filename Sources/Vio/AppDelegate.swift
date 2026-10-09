import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let dictation = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        dictation.onStateChange = { [weak self] state in
            self?.updateAppearance(for: state)
        }
        dictation.onError = { [weak self] title, message, pane in
            self?.showError(title: title, message: message, settingsPane: pane)
        }

        HotkeyCenter.shared.onTrigger = { [weak self] pressed in
            pressed ? self?.dictation.press() : self?.dictation.release()
        }
        do {
            try HotkeyCenter.shared.update(hotkey: AppSettings.hotkey)
        } catch {
            showError(title: "Dictation shortcut unavailable", message: error.localizedDescription, settingsPane: nil)
        }

        NotificationCenter.default.addObserver(
            forName: .vioHotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTooltip()
        }

        SpeechEngine.shared.preload()
        updateAppearance(for: .idle)

        if !Paster.isTrusted {
            // Simulated ⌘V requires Accessibility permission.
            // Re-signing a rebuild can invalidate the previous grant.
            showError(
                title: "Enable Accessibility to paste automatically",
                message: "Allow Vio in System Settings › Privacy & Security › Accessibility to paste transcripts with ⌘V. Until then, Vio copies them to the clipboard. You can grant access without restarting Vio.",
                settingsPane: "Privacy_Accessibility"
            )
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Vio",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    private func updateAppearance(for state: DictationController.State) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch state {
        case .idle:
            symbol = "waveform"
        case .recording:
            symbol = "record.circle"
        case .transcribing, .cleaning:
            symbol = "hourglass"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = state == .recording ? .systemRed : nil
        updateTooltip()
    }

    private func updateTooltip() {
        guard let button = statusItem?.button else { return }
        let shortcut = AppSettings.hotkey.displayString
        let verb = AppSettings.pushToTalk ? "hold" : "press"
        switch dictation.state {
        case .idle:
            button.toolTip = "Vio, \(verb) \(shortcut) to dictate"
        case .recording:
            button.toolTip = "Recording, \(verb) \(shortcut) to transcribe"
        case .transcribing:
            button.toolTip = "Transcribing…"
        case .cleaning:
            button.toolTip = "Cleaning up…"
        }
    }

    // MARK: Errors

    private func showError(title: String, message: String, settingsPane: String?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if settingsPane != nil { alert.addButton(withTitle: "Open System Settings") }
        alert.addButton(withTitle: "OK")
        if settingsPane != nil, alert.runModal() == .alertFirstButtonReturn,
           let pane = settingsPane,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
