# Vio

Vio is a macOS menu-bar app for speech-to-text dictation. Hold a hotkey, speak, and release it to paste the transcript into your app.

Transcription runs on your Mac with [Whistle](https://cactuscompute.com/blog/whistle), a 16.9 MB on-device speech model running in the [needle](https://github.com/cactus-compute/needle) engine (CPU, no server calls, no telemetry).

## Requirements

- Apple Silicon Mac running macOS 26 or newer (the prebuilt engine targets macOS 26 / arm64)
- Xcode 26 or newer with command line tools (`xcodebuild`/`swift`)
- Python 3.11 or newer for asset verification and download scripts

Local builds have been checked with Xcode 27.0 and Swift 6.4. CI runs on macOS 26.

## Build & run

```bash
make app     # builds release, assembles and ad-hoc signs build/Vio.app
make open    # builds and launches it
```

The engine (`Vendor/`) and model (`Resources/whistle.cact`) are vendored in the repo. If they are missing, fetch them from Hugging Face:

```bash
make download
```

Check the app with generated speech, or supply a 16-bit PCM WAV file:

```bash
make selftest
make selftest WAV="path/to/recording.wav"
make test
```

`make app` verifies the bundled assets before building. `make download` uses
pinned revisions and checks SHA-256 before replacing files.

## First run

Vio asks for microphone access on your first dictation and Accessibility access at launch. It uses Accessibility to paste transcripts with ⌘V. Without that permission, Vio copies transcripts to the clipboard.

## Usage

Open Settings… from the menu bar to change the dictation shortcut, turn hold-to-talk on or off, or launch Vio at login. You can also choose a language and add custom words.

Hold the dictation shortcut, ⌥Space by default, to record. Release it to stop and transcribe. Hold-to-talk is enabled by default. A pulsing red indicator appears near the text caret, or at the top-center of the screen if caret bounds are unavailable. The menu-bar icon turns red. Vio shows an hourglass while it transcribes.

Vio pastes with ⌘V if the original field still has focus, preserving the target app's undo behavior. If you switched fields or apps, it tries to insert the text into the original field through Accessibility. If that fails, it pastes with ⌘V into the current field. Without Accessibility permission, or when Vio is frontmost, it leaves the transcript on the clipboard. After a ⌘V paste, Vio restores your previous clipboard text if you had any and haven't copied other text in the meantime.

Turn off Hold to talk in Settings to press the shortcut once to start recording and again to stop. Carbon hot-key events capture both press and release without extra permissions.

To change the shortcut, click its recorder in Settings and press a combination containing ⌘, ⌥, or ⌃. Press Esc to cancel.

Vio transcribes long recordings in 25-second chunks because the model limits clips to 30 seconds. Recording stops after 10 minutes to limit memory use. A double-tap shorter than about 0.1 seconds cancels recording.

## Accuracy

Choose a language in Settings to avoid auto-detection on short clips. Add names and jargon under Custom words to make the recognizer prefer them.

Whistle is a 16.9 MB model for on-device CPU transcription. The same Cactus project offers the [`cactus` engine](https://cactuscompute.com/docs/v1.7/transcription) with larger Whisper small/medium models. Switching engines requires code changes.

## Troubleshooting

If Vio copies transcripts but doesn't paste them, check its Accessibility permission in System Settings › Privacy & Security › Accessibility. Re-signing a rebuild can invalidate the previous grant. Grant access again without restarting Vio.

Vio shows an alert at launch and during dictation if Accessibility permission is missing. Check Console for `vio paste: …` messages to see which delivery method it used.

## Known limitations

- Vio supports Apple Silicon and macOS 26 or newer. The bundled engine does not support Intel Macs.
- Fixed 25-second chunk boundaries can split words. Vio stops recording after 10 minutes.
- If direct insertion into the original field fails after a focus change, Vio pastes into the current field. Check the destination before stopping dictation.
- Clipboard restoration covers text only and uses a 0.4-second delay. Apps that read pasted text after that delay may receive the previous clipboard text.
- Local builds use ad-hoc signing. They are not notarized, and rebuilding can invalidate permission grants.

## Project layout

```
Sources/Vio/    AppKit menu-bar app and SwiftUI settings
Tests/          Swift regression tests and download-script tests
Scripts/        Pinned asset manifest and verification/download script
Vendor/         Needle C header, module map, and prebuilt arm64 engine
Resources/      Whistle speech model
Licenses/       Apache-2.0 license for bundled dependencies
```

See [Contributing](CONTRIBUTING.md) for development instructions and
[manual checks](docs/manual-testing.md) for permission and paste testing.

## License and credits

Vio uses the [MIT license](LICENSE). The bundled [Needle engine](https://github.com/cactus-compute/needle)
and [Whistle model](https://huggingface.co/Cactus-Compute/whistle) by Cactus Compute
retain their Apache-2.0 license. See [third-party notices](THIRD_PARTY_NOTICES.md)
for exact asset revisions and license details.
