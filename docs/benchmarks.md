# Transcription benchmark

Measured on October 9, 2026 with the bundled Whistle model, a release build,
English recognition, and no custom words. Hardware: Apple M2 Pro,
32 GB RAM, macOS 27.

Generate the two speech clips and run the benchmark from the repository root:

```bash
swift build -c release
mkdir -p build/benchmarks
say -v Samantha -r 180 -o build/benchmarks/short.aiff 'Please send the updated design to the team before our meeting tomorrow morning.'
say -v Samantha -r 180 -o build/benchmarks/long.aiff 'I reviewed the latest version of the application this morning. The settings are easy to find, and the new keyboard shortcut works well. Please send the updated design to the team before our meeting tomorrow. We should also check the documentation and make sure the installation steps are clear for everyone.'
for clip in short long; do
    afconvert -f WAVE -d LEI16@16000 -c 1 "build/benchmarks/$clip.aiff" "build/benchmarks/$clip.wav"
    VIO_MODEL_PATH="$PWD/Resources/whistle.cact" .build/release/Vio \
        --selftest "build/benchmarks/$clip.wav" --benchmark -VioLanguage en -VioKeywords ''
done
```

`--benchmark` loads the model, prints one warm-up transcript, then measures five
transcriptions of the same audio through `SpeechEngine.transcribe`. It reports
the median and audio duration divided by that median. WAV decoding, recording,
cleanup, and paste delivery are outside the timed region. Model load is measured
separately and includes reading the file, but does not clear the OS file cache.
This is a small synthetic-speech benchmark, not an accuracy evaluation.

Recorded transcription times in seconds:

| Clip | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 |
| --- | --- | --- | --- | --- | --- |
| 3.98 s | 0.032 | 0.031 | 0.030 | 0.031 | 0.032 |
| 16.24 s | 0.128 | 0.127 | 0.126 | 0.128 | 0.124 |

Both generated clips transcribed to their source text. To measure a real recording,
replace the WAV path in the command above with your own 16-bit PCM WAV file.
