import AppKit
import AVFoundation

/// Drives the record → transcribe → paste cycle behind the hotkey.
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning
    }

    var onStateChange: ((State) -> Void)?
    /// (title, message, optional System Settings privacy pane to offer)
    var onError: ((String, String, String?) -> Void)?

    private let recorder = AudioRecorder()
    private let cleaner: TranscriptCleaner
    private let transcribe: ([Float]) throws -> String
    private let paste: (String, AXUIElement?) -> Bool
    private let showIndicator: (AXUIElement?, String) -> Void
    private let hideIndicator: () -> Void
    private var target: AXUIElement?
    private var warnedPasteBlocked = false
    private(set) var state: State = .idle {
        didSet {
            if oldValue != state { onStateChange?(state) }
        }
    }

    init(
        cleaner: TranscriptCleaner = TranscriptCleaner(),
        transcribe: @escaping ([Float]) throws -> String = { try SpeechEngine.shared.transcribe($0) },
        paste: @escaping (String, AXUIElement?) -> Bool = { Paster.pasteOrCopy($0, into: $1) },
        showIndicator: @escaping (AXUIElement?, String) -> Void = {
            RecordingIndicator.shared.show(caret: Paster.caretRect(for: $0), hint: $1)
        },
        hideIndicator: @escaping () -> Void = { RecordingIndicator.shared.hide() }
    ) {
        self.cleaner = cleaner
        self.transcribe = transcribe
        self.paste = paste
        self.showIndicator = showIndicator
        self.hideIndicator = hideIndicator
    }

    /// Starts recording, or stops on the second press in toggle mode.
    /// In push-to-talk mode, release stops recording.
    func press() {
        switch state {
        case .idle:
            start()
        case .recording:
            if !AppSettings.pushToTalk { recorder.stop() }
        case .transcribing, .cleaning:
            break
        }
    }

    /// Hotkey released (push-to-talk).
    func release() {
        if AppSettings.pushToTalk, state == .recording {
            recorder.stop()
        }
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.beginRecording() : self?.failMicrophone()
                }
            }
        default:
            failMicrophone()
        }
    }

    private func beginRecording() {
        target = Paster.captureFocusedElement()
        do {
            try recorder.start { [weak self] samples in
                guard let self else { return }
                self.handleCapturedSamples(samples, into: self.target)
            }
            state = .recording
            let shortcut = AppSettings.hotkey.displayString
            let hint = AppSettings.pushToTalk
                ? "Listening, release \(shortcut) to transcribe"
                : "Listening, press \(shortcut) to stop"
            showIndicator(target, hint)
        } catch {
            onError?("Can't start recording", error.localizedDescription, "Privacy_Microphone")
        }
    }

    func handleCapturedSamples(_ samples: [Float], into target: AXUIElement?) {
        // A double-tap of the hotkey shorter than ~0.1 s is treated as a cancel.
        guard samples.count >= 1600 else {
            state = .idle
            hideIndicator()
            return
        }

        let cleanupEnabled = AppSettings.cleanupEnabled
        state = .transcribing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.transcribe(samples) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let text):
                    var output = text
                    if cleanupEnabled, !text.isEmpty, self.cleaner.availability == .available {
                        self.state = .cleaning
                        self.showIndicator(target, "Cleaning up…")
                        output = await self.cleaner.clean(text, enabled: cleanupEnabled)
                    }
                    self.hideIndicator()
                    if !output.isEmpty, !self.paste(output, target),
                       !Paster.isTrusted, !self.warnedPasteBlocked {
                        self.warnedPasteBlocked = true
                        self.onError?(
                            "Couldn't paste the transcript",
                            "It was copied to the clipboard instead. Allow Vio in System Settings › Privacy & Security › Accessibility so transcripts are typed directly into your apps.",
                            "Privacy_Accessibility"
                        )
                    }
                case .failure(let error):
                    self.hideIndicator()
                    self.onError?("Transcription failed", error.localizedDescription, nil)
                }
                self.state = .idle
                self.target = nil
            }
        }
    }

    private func failMicrophone() {
        onError?(
            "Microphone access needed",
            "Vio needs microphone access to record your speech. Allow it in System Settings › Privacy & Security › Microphone.",
            "Privacy_Microphone"
        )
    }
}
