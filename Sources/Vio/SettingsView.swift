import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var hotkey = AppSettings.hotkey
    @State private var pushToTalk = AppSettings.pushToTalk
    @State private var shortcutError: String?
    @State private var language = AppSettings.language
    @State private var keywords = UserDefaults.standard.string(forKey: "VioKeywords") ?? ""
    @FocusState private var keywordsFocused: Bool

    private static let languages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"), ("de", "German"), ("fr", "French"), ("es", "Spanish"),
        ("it", "Italian"), ("nl", "Dutch"), ("pl", "Polish"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            if !LoginItem.setEnabled(enabled) {
                                launchAtLogin = false
                            }
                        }
                }

                Section {
                    Toggle("Hold to talk", isOn: $pushToTalk)
                        .onChange(of: pushToTalk) { _, enabled in
                            AppSettings.pushToTalk = enabled
                        }

                    LabeledContent("Keyboard shortcut") {
                        HotkeyRecorder(hotkey: $hotkey) { newValue in
                            do {
                                try AppSettings.setHotkey(newValue)
                                shortcutError = nil
                            } catch {
                                hotkey = AppSettings.hotkey
                                shortcutError = error.localizedDescription
                            }
                        }
                        .frame(width: 130, height: 30)
                        .help("Click to record a shortcut. Press Escape to cancel.")
                    }
                } header: {
                    Text("Dictation")
                } footer: {
                    Text(pushToTalk
                         ? "Hold the shortcut to speak. Release to transcribe and insert text."
                         : "Press the shortcut to start dictating. Press again to transcribe and insert text.")
                }

                Section("Recognition") {
                    Picker("Language", selection: $language) {
                        ForEach(Self.languages, id: \.code) { entry in
                            Text(entry.name).tag(entry.code)
                        }
                    }
                    .onChange(of: language) { _, code in
                        AppSettings.language = code
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom words")
                        TextField("Custom words", text: $keywords,
                                  prompt: Text("Names, acronyms, or technical terms")
                                    .foregroundStyle(.tertiary),
                                  axis: .vertical)
                            .labelsHidden()
                            .font(.body.weight(.regular))
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                            .focused($keywordsFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(keywordsFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                                                  lineWidth: keywordsFocused ? 1.5 : 1)
                            }
                            .accessibilityLabel("Custom words")
                            .onChange(of: keywords) { _, words in
                                AppSettings.keywords = words
                            }
                        Text("Separate words and phrases with commas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)

            Link(destination: URL(string: "https://github.com/apvarun/vio")!) {
                Label("Vio on GitHub", systemImage: "arrow.up.right.square")
                    .font(.callout)
            }
            .help("Open github.com/apvarun/vio in your browser")
            .padding(.bottom, 20)
        }
        .frame(width: 520, height: 570)
        .alert("Dictation shortcut unavailable", isPresented: Binding(
            get: { shortcutError != nil },
            set: { if !$0 { shortcutError = nil } }
        )) {
            Button("OK", role: .cancel) { shortcutError = nil }
        } message: {
            Text(shortcutError ?? "")
        }
    }
}

/// A control that records a keyboard shortcut when clicked.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    var onCommit: (Hotkey) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.hotkey = hotkey
        view.onCommit = { newValue in
            self.hotkey = newValue
            self.onCommit(newValue)
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderView, context: Context) {
        if !nsView.isRecording {
            nsView.hotkey = hotkey
        }
    }
}

final class HotkeyRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    var onCommit: ((Hotkey) -> Void)?
    var hotkey: Hotkey {
        didSet { refreshLabel() }
    }
    private(set) var isRecording = false

    override init(frame frameRect: NSRect) {
        hotkey = .standard
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        hotkey = .standard
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshLabel()
        applyColors(active: false)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            isRecording = true
            label.stringValue = "Press shortcut…"
            applyColors(active: true)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshLabel()
        applyColors(active: false)
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels recording without changing the shortcut.
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        // Ignore modifier keys until the user presses a non-modifier key.
        if Self.modifierKeyCodes.contains(event.keyCode) { return }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])

        // A shortcut without ⌘, ⌥ or ⌃ would swallow plain typing system-wide.
        guard modifiers.intersection([.command, .option, .control]).isEmpty == false else {
            flashHint()
            return
        }

        let newHotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers.rawValue)
        hotkey = newHotkey
        window?.makeFirstResponder(nil)
        onCommit?(newHotkey)
    }

    private func refreshLabel() {
        label.stringValue = hotkey.displayString
        label.textColor = .labelColor
    }

    private func flashHint() {
        label.stringValue = "Add ⌘, ⌥ or ⌃"
        label.textColor = .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshLabel()
        }
    }

    private func applyColors(active: Bool) {
        layer?.backgroundColor = NSColor.controlColor.cgColor
        layer?.borderColor = (active ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        applyColors(active: isRecording)
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_CapsLock), UInt16(kVK_Function),
    ]
}
