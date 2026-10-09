import Foundation
import CNeedle

enum EngineError: LocalizedError {
    case modelMissing(String)
    case loadFailed(String)
    case transcriptionFailed(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .modelMissing(let path):
            return "Speech model not found at \(path). Reinstall the app or set VIO_MODEL_PATH."
        case .loadFailed(let detail):
            return "Could not load the speech model: \(detail)"
        case .transcriptionFailed(let detail):
            return "Transcription failed: \(detail)"
        case .badResponse:
            return "The speech engine returned an unreadable response."
        }
    }
}

/// Wraps the needle runtime. The runtime is process-global and not thread-safe,
/// so `transcribe` and `loadIfNeeded` use `lock` to serialize access.
final class SpeechEngine {
    static let shared = SpeechEngine()

    private let lock = NSLock()
    private var modelData: Data?
    private var loaded = false
    private(set) var loadError: String?

    var modelURL: URL? {
        if let override = ProcessInfo.processInfo.environment["VIO_MODEL_PATH"] {
            return URL(fileURLWithPath: override)
        }
        return Bundle.main.url(forResource: "whistle", withExtension: "cact")
    }

    func preload() {
        DispatchQueue.global(qos: .utility).async { [self] in
            _ = try? loadIfNeeded()
        }
    }

    @discardableResult
    func loadIfNeeded() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return try loadIfNeededLocked()
    }

    private func loadIfNeededLocked() throws -> Bool {
        if loaded { return true }
        guard let url = modelURL else {
            throw EngineError.modelMissing("whistle.cact (app bundle)")
        }
        do {
            modelData = try Data(contentsOf: url)
        } catch {
            loadError = error.localizedDescription
            throw EngineError.loadFailed(error.localizedDescription)
        }
        // The runtime keeps references into the loaded bytes, so modelData must
        // stay alive for the lifetime of the process.
        let rc = modelData!.withUnsafeBytes { raw in
            needle_load(raw.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt64(modelData!.count))
        }
        if rc < 0 {
            let detail = String(cString: needle_last_error())
            modelData = nil
            loadError = detail
            throw EngineError.loadFailed(detail)
        }
        loaded = true
        loadError = nil
        return true
    }

    /// Transcribes 16 kHz mono float PCM in [-1, 1] and returns the trimmed
    /// text. Whistle rejects clips over 30 s, so long takes are transcribed
    /// in 25 s chunks and joined.
    func transcribe(_ samples: [Float]) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        _ = try loadIfNeededLocked()

        let language = AppSettings.language == "auto" ? nil : AppSettings.language
        let keywords = AppSettings.keywords.isEmpty ? nil : AppSettings.keywords

        let chunkLength = 25 * 16000
        var texts: [String] = []
        var start = samples.startIndex
        while start < samples.endIndex {
            let end = min(start + chunkLength, samples.endIndex)
            texts.append(try transcribeChunk(samples[start..<end], language: language, keywords: keywords))
            start = end
        }
        return texts
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // Fixed 25 s chunk boundaries can split words.
    private func transcribeChunk(_ slice: ArraySlice<Float>, language: String?, keywords: String?) throws -> String {
        let samples = Array(slice)
        var out = [CChar](repeating: 0, count: 65536)
        let rc: Int32 = withNullableCString(language) { lang in
            withNullableCString(keywords) { kw in
                samples.withUnsafeBufferPointer { pcm in
                    needle_transcribe(pcm.baseAddress, Int32(pcm.count), lang, kw, 0, &out, Int32(out.count))
                }
            }
        }
        if rc < 0 {
            throw EngineError.transcriptionFailed(String(cString: needle_last_error()))
        }

        let payload = String(cString: out)
        guard let data = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = object["text"] as? String else {
            throw EngineError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withNullableCString<Result>(_ value: String?, _ body: (UnsafePointer<CChar>?) throws -> Result) rethrows -> Result {
        guard var buffer = value.map({ Array($0.utf8CString) }) else {
            return try body(nil)
        }
        return try buffer.withUnsafeMutableBufferPointer { raw in
            try body(raw.baseAddress)
        }
    }
}
