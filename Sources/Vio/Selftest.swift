import Foundation

/// `Vio --selftest recording.wav` checks the bundled engine without opening the GUI.
enum Selftest {
    static func inputURL(arguments: [String]) -> URL? {
        guard let flag = arguments.firstIndex(of: "--selftest"),
              arguments.indices.contains(flag + 1),
              !arguments[flag + 1].hasPrefix("--") else { return nil }
        return URL(fileURLWithPath: (arguments[flag + 1] as NSString).expandingTildeInPath)
    }

    static func run() -> Never {
        guard let url = inputURL(arguments: CommandLine.arguments) else {
            FileHandle.standardError.write(Data("usage: Vio --selftest recording.wav\n".utf8))
            exit(64)
        }
        do {
            let samples = try WavReader.mono16kSamples(from: url)
            try SpeechEngine.shared.loadIfNeeded()
            let text = try SpeechEngine.shared.transcribe(samples)
            print(text.isEmpty ? "(silence, no speech detected)" : text)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("selftest failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

/// Reads 16-bit PCM WAV files, downmixes to mono, and resamples to 16 kHz.
enum WavReader {
    enum Error: LocalizedError {
        case notAWav
        case unsupportedFormat(UInt16)

        var errorDescription: String? {
            switch self {
            case .notAWav: return "The WAV file is incomplete or has invalid audio metadata."
            case .unsupportedFormat(let format): return "Expected 16-bit PCM WAV audio. Format code: \(format)."
            }
        }
    }

    static func mono16kSamples(from url: URL) throws -> [Float] {
        try mono16kSamples(from: Data(contentsOf: url))
    }

    static func mono16kSamples(from data: Data) throws -> [Float] {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(u16(offset)) | (UInt32(u16(offset + 2)) << 16)
        }
        func chunkID(_ offset: Int) -> String {
            String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
        }
        guard bytes.count >= 12, chunkID(0) == "RIFF", chunkID(8) == "WAVE" else {
            throw Error.notAWav
        }
        let riffEnd = Int(u32(4)) + 8
        guard riffEnd >= 12, riffEnd <= bytes.count else { throw Error.notAWav }

        var channels = 0
        var sampleRate = 0
        var blockAlign = 0
        var dataRange: Range<Int>?
        var offset = 12
        while offset < riffEnd {
            guard offset + 8 <= riffEnd else { throw Error.notAWav }
            let id = chunkID(offset)
            let size = Int(u32(offset + 4))
            let body = offset + 8
            guard size <= riffEnd - body else { throw Error.notAWav }
            switch id {
            case "fmt ":
                guard size >= 16 else { throw Error.notAWav }
                let format = u16(body)
                channels = Int(u16(body + 2))
                sampleRate = Int(u32(body + 4))
                blockAlign = Int(u16(body + 12))
                guard channels > 0, sampleRate > 0 else { throw Error.notAWav }
                guard u16(body + 14) == 16, blockAlign == channels * 2 else {
                    throw Error.unsupportedFormat(format)
                }
                if format == 0xFFFE {
                    // WAVE_FORMAT_EXTENSIBLE must identify 16-bit PCM, not float audio.
                    let pcmGUID: [UInt8] = [1, 0, 0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]
                    guard size >= 40, u16(body + 16) >= 22,
                          Int(u16(body + 16)) + 18 <= size,
                          u16(body + 18) == 16,
                          Array(bytes[body + 24..<body + 40]) == pcmGUID else {
                        throw Error.unsupportedFormat(format)
                    }
                } else if format != 1 {
                    throw Error.unsupportedFormat(format)
                }
            case "data": dataRange = body..<body + size
            default: break
            }
            offset = body + size + size % 2
            guard offset <= riffEnd else { throw Error.notAWav }
        }
        guard let dataRange, channels > 0, sampleRate > 0,
              blockAlign > 0, dataRange.count % blockAlign == 0 else { throw Error.notAWav }
        let frames = dataRange.count / blockAlign
        guard frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                let position = dataRange.lowerBound + frame * blockAlign + channel * 2
                sum += Float(Int16(bitPattern: u16(position))) / 32768.0
            }
            mono[frame] = sum / Float(channels)
        }
        guard sampleRate != 16000 else { return mono }
        let targetCount = Int((Double(frames) * 16000 / Double(sampleRate)).rounded())
        var resampled = [Float](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let position = Double(i) * Double(sampleRate) / 16000
            let index = Int(position)
            let fraction = Float(position - Double(index))
            let current = mono[min(index, frames - 1)]
            let next = mono[min(index + 1, frames - 1)]
            resampled[i] = current + (next - current) * fraction
        }
        return resampled
    }
}
