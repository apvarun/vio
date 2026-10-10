# Vio

Vio is a macOS menu-bar app for local speech-to-text dictation. Hold ⌥Space, speak, and release to paste into the app you're using.

Transcription runs on your Mac's CPU with the 16.9 MB [Whistle model](https://huggingface.co/Cactus-Compute/whistle) and [Needle engine](https://github.com/cactus-compute/needle), without server calls or telemetry.

[![Build and test](https://github.com/apvarun/vio/actions/workflows/ci.yml/badge.svg)](https://github.com/apvarun/vio/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Download and install

[Download Vio for Mac](https://github.com/apvarun/vio/releases/download/v0.1.0/Vio-0.1.0-arm64.dmg) · [Latest release](https://github.com/apvarun/vio/releases/latest)

Requires an Apple Silicon Mac, such as an M1 or newer, running macOS 26 or newer. The app includes the speech model and works offline. You don't need Xcode or any extra downloads.

1. Download and open the `.dmg` file.
2. Drag Vio into Applications, then open Vio from Applications.
3. Allow Vio in System Settings › Privacy & Security › Accessibility so it can paste your dictation.

Vio runs in the menu bar. Click its icon to open Settings or quit.

## Use Vio

1. Click a text field in the app where you want to write.
2. Hold Option + Space, shown as ⌥Space, and allow microphone access when macOS asks. Speak while holding the keys.
3. Release the keys. Vio transcribes your speech and pastes the text into the field.

Open Settings from the menu bar to change the shortcut, choose a language, add custom words, or launch at login. English is the default language. Turn off Hold to talk to press once to start recording and again to stop.

Optional transcript cleanup uses Apple's on-device Foundation Models to fix punctuation and grammar and remove fillers. It requires Apple Intelligence, is off by default, and can add up to eight seconds before pasting. If cleanup fails or times out, Vio delivers the original transcript. Model edits can make mistakes.

## Troubleshooting

- If your transcript doesn't appear in the text field, press Command + V to paste it. Check that Vio has access in System Settings › Privacy & Security › Accessibility.
- If Vio can't record, allow it in System Settings › Privacy & Security › Microphone.
- If the shortcut conflicts with another app, change it in Vio's Settings.
- If pasting stops working after an update or rebuild, grant Accessibility access again.

## Limitations

- Recordings stop after 10 minutes. Fixed 25-second transcription chunks can split words.
- Switching fields during dictation can send text to the current field if insertion into the original field fails.
- Clipboard restoration preserves text only. Apps that read the clipboard more than 0.4 seconds after pasting may receive the previous text.

## Performance

On an Apple M2 Pro with 32 GB RAM and macOS 27, a release build transcribed 3.98 seconds of generated English speech in 31 ms and 16.24 seconds in 127 ms. These are median engine-only timings; recording, decoding, cleanup, and pasting are excluded. See [benchmark details and reproduction steps](docs/benchmarks.md).

## Build and run

Requires an Apple Silicon Mac with macOS 26+, Xcode 26+ with command line tools, and Python 3.11+.

```bash
git clone https://github.com/apvarun/vio.git
cd vio
make open
```

This builds and launches `build/Vio.app`. Use `make app` to build without launching. The app uses ad-hoc signing and is not notarized.

The engine and model are bundled. If asset verification fails, run `make download` to restore them, then retry.

## Build an installer

Run `make dmg` to build the dark teal drag-to-Applications installer. Install its
packaging dependency with `brew install create-dmg` first. Local previews are not
notarized.

Run `make release` with `SIGNING_IDENTITY` and `NOTARY_PROFILE` configured to
produce a signed, notarized DMG and SHA-256 checksum. See the
[release instructions](docs/releases.md) for Keychain setup and publishing.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, tests, and pull request guidance. [Report bugs](https://github.com/apvarun/vio/issues) with steps to reproduce, your Vio version, and your macOS version. Include your Xcode version if you built Vio from source. Don't include private recordings or transcripts.

## License

Vio uses [MIT](LICENSE). The bundled Needle engine and Whistle model by Cactus Compute retain Apache-2.0. See [third-party notices](THIRD_PARTY_NOTICES.md).
