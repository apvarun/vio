import AppKit
import AVFoundation

/// Drives the record → transcribe → paste cycle behind the hotkey.
final class DictationController {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    var onStateChange: ((State) -> Void)?
    /// (title, message, optional System Settings privacy pane to offer)
    var onError: ((String, String, String?) -> Void)?

    private let recorder = AudioRecorder()
    private var target: AXUIElement?
    private var warnedPasteBlocked = false
    private(set) var state: State = .idle {
        didSet {
            if oldValue != state { onStateChange?(state) }
        }
    }

    /// Starts recording, or stops on the second press in toggle mode.
    /// In push-to-talk mode, release stops recording.
    func press() {
        switch state {
        case .idle:
            start()
        case .recording:
            if !AppSettings.pushToTalk { recorder.stop() }
        case .transcribing:
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
                self?.handleCapturedSamples(samples)
            }
            state = .recording
            let shortcut = AppSettings.hotkey.displayString
            let hint = AppSettings.pushToTalk
                ? "Listening, release \(shortcut) to transcribe"
                : "Listening, press \(shortcut) to stop"
            RecordingIndicator.shared.show(caret: Paster.caretRect(for: target), hint: hint)
        } catch {
            onError?("Can't start recording", error.localizedDescription, "Privacy_Microphone")
        }
    }

    private func handleCapturedSamples(_ samples: [Float]) {
        // A double-tap of the hotkey shorter than ~0.1 s is treated as a cancel.
        guard samples.count >= 1600 else {
            state = .idle
            RecordingIndicator.shared.hide()
            return
        }

        state = .transcribing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<String, Error> = Result {
                try SpeechEngine.shared.transcribe(samples)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = .idle
                RecordingIndicator.shared.hide()
                switch result {
                case .success(let text):
                    if !text.isEmpty, !Paster.pasteOrCopy(text, into: self.target),
                       !Paster.isTrusted, !self.warnedPasteBlocked {
                        self.warnedPasteBlocked = true
                        self.onError?(
                            "Couldn't paste the transcript",
                            "It was copied to the clipboard instead. Allow Vio in System Settings › Privacy & Security › Accessibility so transcripts are typed directly into your apps.",
                            "Privacy_Accessibility"
                        )
                    }
                case .failure(let error):
                    self.onError?("Transcription failed", error.localizedDescription, nil)
                }
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
