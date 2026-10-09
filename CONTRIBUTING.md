# Contributing

Vio needs an Apple Silicon Mac running macOS 26 or newer, Xcode 26 or newer,
and Python 3.11 or newer. The bundled engine targets macOS 26 and arm64.

```sh
make verify-assets
make test
make app
make selftest
```

`make download` restores missing or modified assets from pinned upstream
revisions. It checks SHA-256 before replacing a file. Don't update the engine,
header, or model without updating `Scripts/assets.json` and checking upstream
licenses and notices.

For a speech sample of your own, use `make selftest WAV="path/to/clip.wav"`.
The WAV reader accepts 16-bit PCM, including PCM WAVE_FORMAT_EXTENSIBLE,
and converts it to 16 kHz mono audio.

For bug reports, include your macOS and Xcode versions, reproduction steps,
and the expected result. Paste delivery messages in Console start with
`vio paste:`. Don't include private recordings or transcripts.

Keep pull requests focused. Add regression tests for parser, settings, or
runtime changes. UI changes need a screenshot and a note about the behaviors
you checked. See [the manual checks](docs/manual-testing.md).

Vio's code uses MIT. Bundled Needle and Whistle files retain Apache-2.0;
see [third-party notices](THIRD_PARTY_NOTICES.md).
